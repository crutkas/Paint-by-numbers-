import SwiftUI
import UIKit
import CoreGraphics
import PBNCore

/// App-wide observable state: the list of puzzles, the currently-imported
/// image waiting to become a puzzle, and the active play session.
@MainActor
final class PuzzleLibrary: ObservableObject {
    @Published var puzzles: [PuzzleMetadata] = []
    @Published var pendingImportImage: UIImage?
    @Published var activePuzzleId: UUID?
    @Published var userFacingError: String?
    var retryAction: (() -> Void)?
    @Published private(set) var progressCache: [UUID: PuzzleProgress] = [:]
    @Published private(set) var thumbnailCache: [UUID: UIImage] = [:]

    let store: PuzzleStore

    init() {
        self.store = PuzzleStore(rootDirectory: AppGroup.puzzlesRootURL)
        Task { await reload() }
    }

    func reload() async {
        do {
            let root = store.rootDirectory
            let result = try await Task.detached {
                try PuzzleStore(rootDirectory: root).listPuzzlesWithRecovery()
            }.value
            puzzles = result.puzzles
            if result.quarantinedPuzzleCount > 0 {
                userFacingError = result.quarantinedPuzzleCount == 1
                    ? "One damaged puzzle was moved aside so the rest of your library could load."
                    : "\(result.quarantinedPuzzleCount) damaged puzzles were moved aside so the rest of your library could load."
            }
        } catch {
            userFacingError = "Your puzzle library could not be loaded. \(error.localizedDescription)"
            retryAction = { [weak self] in
                Task { await self?.reload() }
            }
        }
    }

    // MARK: Incoming content

    func handleIncomingURL(_ url: URL) async {
        // `ShareImport.token(from:)` applies a strict allowlist (UUID-safe
        // characters only), so the returned token is safe to use as a path
        // component. Re-validating here defensively rejects any token that
        // might have been obtained through another code path.
        guard let token = ShareImport.token(from: url), ShareImport.isValidToken(token) else {
            userFacingError = "The shared image link is invalid."
            retryAction = nil
            return
        }

        let inbox = AppGroup.sharedInboxURL.resolvingSymlinksInPath().standardizedFileURL
        let metaURL = inbox.appendingPathComponent("\(token).json")
        let payload: ShareImportPayload
        do {
            payload = try await Task.detached {
                try Self.validateInboxFile(metaURL, inside: inbox)
                return try JSONDecoder().decode(
                    ShareImportPayload.self,
                    from: Data(contentsOf: metaURL, options: .mappedIfSafe)
                )
            }.value
        } catch {
            userFacingError = "The shared image information is invalid. \(error.localizedDescription)"
            return
        }

        guard payload.token == token,
              ShareImport.isValidToken(payload.token),
              ShareImport.isSafeFilename(payload.filename) else {
            userFacingError = "The shared image information does not match this import request."
            return
        }

        let imageURL = inbox.appendingPathComponent(payload.filename)
        do {
            pendingImportImage = try await Task.detached {
                try Self.validateInboxFile(imageURL, inside: inbox)
                return try ImageImportValidator.image(
                    from: Data(contentsOf: imageURL, options: .mappedIfSafe)
                )
            }.value
        } catch {
            userFacingError = "The shared image could not be opened safely. \(error.localizedDescription)"
            return
        }

        do {
            try await Task.detached {
                try FileManager.default.removeItem(at: metaURL)
                try FileManager.default.removeItem(at: imageURL)
            }.value
        } catch {
            userFacingError = "The image was imported, but its temporary files could not be removed."
            retryAction = { [weak self] in
                Task {
                    do {
                        try await Task.detached {
                            if FileManager.default.fileExists(atPath: metaURL.path) {
                                try FileManager.default.removeItem(at: metaURL)
                            }
                            if FileManager.default.fileExists(atPath: imageURL.path) {
                                try FileManager.default.removeItem(at: imageURL)
                            }
                        }.value
                    } catch {
                        self?.userFacingError = "Temporary files still could not be removed. \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    func handleImportedFile(_ url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard (values.fileSize ?? 0) <= ImageImportValidator.maximumFileBytes else {
                throw ImageImportValidator.ValidationError.tooLarge
            }
            pendingImportImage = try await Task.detached {
                try ImageImportValidator.image(from: Data(contentsOf: url))
            }.value
        } catch {
            userFacingError = "The image could not be imported. \(error.localizedDescription)"
            retryAction = { [weak self] in
                Task { await self?.handleImportedFile(url) }
            }
        }
    }

    func handleDroppedProviders(_ providers: [NSItemProvider]) {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier("public.image") }) else {
            userFacingError = "The dropped item is not a supported image."
            return
        }
        provider.loadDataRepresentation(forTypeIdentifier: "public.image") { [weak self] data, error in
            Task { @MainActor [weak self] in
                guard let data else {
                    self?.userFacingError = error?.localizedDescription ?? "The dropped image could not be read."
                    return
                }
                do {
                    self?.pendingImportImage = try await Task.detached {
                        try ImageImportValidator.image(from: data)
                    }.value
                } catch {
                    self?.userFacingError = error.localizedDescription
                }
            }
        }
    }

    // MARK: Puzzle lifecycle

    /// Build a puzzle on a background queue and persist metadata + source
    /// image + lossless region map.
    ///
    /// The detached background task is intentionally limited to pure
    /// computation (`PuzzleGenerator.generate` and `image.pngData()`); all
    /// persistence is funnelled back to the main actor so the shared
    /// `PuzzleStore` / `JSONEncoder` isn't accessed concurrently.
    func createPuzzle(
        fromImage image: UIImage,
        title: String,
        difficulty: Difficulty,
        strategy: GridStrategy
    ) async -> PuzzleMetadata? {
        guard let rgb = image.rgbImage() else {
            userFacingError = "The image could not be prepared for painting."
            return nil
        }

        // 1. Expensive, side-effect-free work on a background thread.
        let result: (generated: PuzzleGenerator.GeneratedPuzzle, sourcePNG: Data, regionMap: Data)
        do {
            result = try await Task.detached(priority: .userInitiated) {
                let generated = PuzzleGenerator.generate(
                    image: rgb,
                    difficulty: difficulty,
                    strategy: strategy
                )
                guard let sourcePNG = image.pngData() else {
                    throw CocoaError(.fileWriteInapplicableStringEncoding)
                }
                let regionMap = try RegionMap.encode(
                    regionIds: generated.regionIds,
                    width: generated.workingWidth,
                    height: generated.workingHeight
                )
                return (generated, sourcePNG, regionMap)
            }.value
        } catch {
            userFacingError = "The puzzle could not be generated. \(error.localizedDescription)"
            return nil
        }

        // 2. Persist with a task-local store so disk I/O never blocks the UI
        //    and JSON encoders are never shared across concurrent operations.
        let generated = result.generated
        let metadata = PuzzleMetadata(
            title: title,
            difficulty: difficulty,
            strategy: strategy,
            workingWidth: generated.workingWidth,
            workingHeight: generated.workingHeight,
            sourcePixelWidth: image.cgImage?.width ?? Int(image.size.width * image.scale),
            sourcePixelHeight: image.cgImage?.height ?? Int(image.size.height * image.scale),
            palette: generated.palette,
            regions: generated.regions,
            sourceImageFilename: "source.png",
            regionMapFilename: "regionMap.pbnr"
        )
        do {
            let root = store.rootDirectory
            try await Task.detached {
                let backgroundStore = PuzzleStore(rootDirectory: root)
                let dir = try backgroundStore.createPuzzleDirectory(id: metadata.id)
                try result.sourcePNG.write(
                    to: dir.appendingPathComponent(metadata.sourceImageFilename),
                    options: .atomic
                )
                try result.regionMap.write(
                    to: dir.appendingPathComponent(metadata.regionMapFilename),
                    options: .atomic
                )
                try backgroundStore.saveProgress(PuzzleProgress(puzzleId: metadata.id))
                // Publish metadata last so an interrupted write cannot expose a
                // puzzle whose source or exact region map is missing.
                try backgroundStore.saveMetadata(metadata)
            }.value
        } catch {
            let saveError = error
            var cleanupMessage = ""
            let root = store.rootDirectory
            do {
                try await Task.detached {
                    try PuzzleStore(rootDirectory: root).delete(id: metadata.id)
                }.value
            } catch {
                cleanupMessage = " Its partial files were preserved for recovery."
            }
            userFacingError = "The puzzle could not be saved. \(saveError.localizedDescription)\(cleanupMessage)"
            retryAction = nil
            await reload()
            return nil
        }
        await reload()
        return metadata
    }

    func progress(for puzzleId: UUID) -> PuzzleProgress {
        progressCache[puzzleId] ?? PuzzleProgress(puzzleId: puzzleId)
    }

    func loadProgress(for puzzle: PuzzleMetadata) async -> PuzzleProgress {
        let root = store.rootDirectory
        let loaded: PuzzleProgress
        do {
            loaded = try await Task.detached {
                try PuzzleStore(rootDirectory: root).loadProgress(id: puzzle.id)
            }.value
        } catch {
            userFacingError = "Progress for “\(puzzle.title)” could not be loaded. \(error.localizedDescription)"
            retryAction = { [weak self] in
                Task { _ = await self?.loadProgress(for: puzzle) }
            }
            let fresh = PuzzleProgress(puzzleId: puzzle.id)
            progressCache[puzzle.id] = fresh
            return fresh
        }
        guard loaded.puzzleId == puzzle.id else {
            userFacingError = "Progress for “\(puzzle.title)” belonged to another puzzle and was reset."
            let fresh = PuzzleProgress(puzzleId: puzzle.id)
            progressCache[puzzle.id] = fresh
            return fresh
        }
        let sanitized = loaded.sanitized(validRegionIds: Set(puzzle.regions.map(\.id)))
        if sanitized != loaded {
            userFacingError = "Invalid saved regions were removed from “\(puzzle.title)”."
            save(progress: sanitized)
        }
        progressCache[puzzle.id] = sanitized
        return sanitized
    }

    func loadRegionIds(for puzzle: PuzzleMetadata) async -> [Int]? {
        let url = store.puzzleDirectory(id: puzzle.id).appendingPathComponent(puzzle.regionMapFilename)
        do {
            return try await Task.detached {
                try RegionMap.decode(
                    Data(contentsOf: url, options: .mappedIfSafe),
                    expectedWidth: puzzle.workingWidth,
                    expectedHeight: puzzle.workingHeight
                )
            }.value
        } catch {
            userFacingError = "The region map for “\(puzzle.title)” is missing or damaged. \(error.localizedDescription)"
            return nil
        }
    }

    func loadThumbnail(for puzzle: PuzzleMetadata) async {
        guard thumbnailCache[puzzle.id] == nil else { return }
        let url = store.puzzleDirectory(id: puzzle.id).appendingPathComponent(puzzle.sourceImageFilename)
        do {
            let image = try await Task.detached {
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                guard let image = UIImage(data: data) else {
                    throw ImageImportValidator.ValidationError.invalidImage
                }
                return image
            }.value
            thumbnailCache[puzzle.id] = image
        } catch {
            userFacingError = "The preview for “\(puzzle.title)” could not be loaded. \(error.localizedDescription)"
            retryAction = { [weak self] in
                Task { await self?.loadThumbnail(for: puzzle) }
            }
        }
    }

    func save(progress: PuzzleProgress) {
        progressCache[progress.puzzleId] = progress
        let root = store.rootDirectory
        Task {
            do {
                try await Task.detached {
                    try PuzzleStore(rootDirectory: root).saveProgress(progress)
                }.value
            } catch {
                userFacingError = "Your painting progress could not be saved. \(error.localizedDescription)"
                retryAction = { [weak self] in self?.save(progress: progress) }
            }
        }
        // Notify observers (e.g. library tiles showing completion %) so
        // they re-render with the latest progress when the player returns
        // to the home screen after painting.
        objectWillChange.send()
    }

    func deletePuzzle(_ id: UUID) {
        let root = store.rootDirectory
        Task {
            do {
                try await Task.detached {
                    try PuzzleStore(rootDirectory: root).delete(id: id)
                }.value
                progressCache[id] = nil
                thumbnailCache[id] = nil
                await reload()
            } catch {
                userFacingError = "The puzzle could not be deleted. \(error.localizedDescription)"
                retryAction = { [weak self] in self?.deletePuzzle(id) }
            }
        }
    }

    private nonisolated static func validateInboxFile(_ file: URL, inside inbox: URL) throws {
        let resolvedInbox = inbox.resolvingSymlinksInPath().standardizedFileURL
        let resolvedFile = file.resolvingSymlinksInPath().standardizedFileURL
        guard resolvedFile.deletingLastPathComponent() == resolvedInbox else {
            throw CocoaError(.fileReadNoPermission)
        }
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw CocoaError(.fileReadNoPermission)
        }
    }
}
