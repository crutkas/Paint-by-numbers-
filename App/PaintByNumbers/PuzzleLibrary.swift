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
            puzzles = try await Task.detached {
                try PuzzleStore(rootDirectory: root).listPuzzles()
            }.value
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

        // Look up the token's metadata and image in the shared inbox.
        let metaURL = AppGroup.sharedInboxURL.appendingPathComponent("\(token).json")
        guard let payload = await Task.detached(operation: {
            guard let data = try? Data(contentsOf: metaURL) else { return nil }
            return try? JSONDecoder().decode(ShareImportPayload.self, from: data)
        }).value,
        ShareImport.isValidToken(payload.token),
        payload.token == token,
        ShareImport.isSafeFilename(payload.filename) else {
            userFacingError = "The shared image information is invalid."
            return
        }
        // The payload's filename is controlled by the Share Extension we ship,
        // but re-check it's not trying to escape the shared inbox folder.
        let inbox = AppGroup.sharedInboxURL.resolvingSymlinksInPath().standardizedFileURL
        let imageURL = inbox.appendingPathComponent(payload.filename).resolvingSymlinksInPath().standardizedFileURL
        guard imageURL.deletingLastPathComponent() == inbox else {
            userFacingError = "The shared image location is unsafe."
            return
        }
        guard let image = await Task.detached(operation: {
            guard let imageData = try? Data(contentsOf: imageURL) else { return nil }
            return try? ImageImportValidator.image(from: imageData)
        }).value else {
            userFacingError = "The shared image could not be opened or is too large."
            return
        }
        pendingImportImage = image

        // Clean up the handoff files now that we've consumed them.
        await Task.detached {
            try? FileManager.default.removeItem(at: metaURL)
            try? FileManager.default.removeItem(at: imageURL)
        }.value
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
        let result: (generated: PuzzleGenerator.GeneratedPuzzle, sourcePNG: Data?, regionMap: Data?) =
            await Task.detached(priority: .userInitiated) {
                let generated = PuzzleGenerator.generate(
                    image: rgb,
                    difficulty: difficulty,
                    strategy: strategy
                )
                let sourcePNG = image.pngData()
                let regionMap = try? RegionMap.encode(
                    regionIds: generated.regionIds,
                    width: generated.workingWidth,
                    height: generated.workingHeight
                )
                return (generated, sourcePNG, regionMap)
            }.value

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
            guard let sourcePNG = result.sourcePNG, let regionMap = result.regionMap else {
                throw CocoaError(.fileWriteUnknown)
            }
            let root = store.rootDirectory
            try await Task.detached {
                let backgroundStore = PuzzleStore(rootDirectory: root)
                do {
                    try backgroundStore.saveMetadata(metadata)
                    let dir = backgroundStore.puzzleDirectory(id: metadata.id)
                    try sourcePNG.write(
                        to: dir.appendingPathComponent(metadata.sourceImageFilename),
                        options: .atomic
                    )
                    try regionMap.write(
                        to: dir.appendingPathComponent(metadata.regionMapFilename),
                        options: .atomic
                    )
                    try backgroundStore.saveProgress(PuzzleProgress(puzzleId: metadata.id))
                } catch {
                    try? backgroundStore.delete(id: metadata.id)
                    throw error
                }
            }.value
        } catch {
            userFacingError = "The puzzle could not be saved. \(error.localizedDescription)"
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
        let loaded = await Task.detached {
            (try? PuzzleStore(rootDirectory: root).loadProgress(id: puzzle.id))
                ?? PuzzleProgress(puzzleId: puzzle.id)
        }.value.sanitized(validRegionIds: Set(puzzle.regions.map(\.id)))
        progressCache[puzzle.id] = loaded
        return loaded
    }

    func loadRegionIds(for puzzle: PuzzleMetadata) async -> [Int]? {
        let url = store.puzzleDirectory(id: puzzle.id).appendingPathComponent(puzzle.regionMapFilename)
        return await Task.detached {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? RegionMap.decode(data, expectedWidth: puzzle.workingWidth, expectedHeight: puzzle.workingHeight)
        }.value
    }

    func loadThumbnail(for puzzle: PuzzleMetadata) async {
        guard thumbnailCache[puzzle.id] == nil else { return }
        let url = store.puzzleDirectory(id: puzzle.id).appendingPathComponent(puzzle.sourceImageFilename)
        let image = await Task.detached {
            guard let data = try? Data(contentsOf: url) else { return nil as UIImage? }
            return UIImage(data: data)
        }.value
        if let image { thumbnailCache[puzzle.id] = image }
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
}
