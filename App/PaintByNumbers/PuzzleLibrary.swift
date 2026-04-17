import SwiftUI
import UIKit
import PBNCore

/// App-wide observable state: the list of puzzles, the currently-imported
/// image waiting to become a puzzle, and the active play session.
@MainActor
final class PuzzleLibrary: ObservableObject {
    @Published var puzzles: [PuzzleMetadata] = []
    @Published var pendingImportImage: UIImage?
    @Published var activePuzzleId: UUID?

    let store: PuzzleStore

    init() {
        self.store = PuzzleStore(rootDirectory: AppGroup.puzzlesRootURL)
        reload()
    }

    func reload() {
        puzzles = (try? store.listPuzzles()) ?? []
    }

    // MARK: Incoming content

    func handleIncomingURL(_ url: URL) {
        guard let token = ShareImport.token(from: url) else { return }
        // Look up the token's metadata and image in the shared inbox.
        let metaURL = AppGroup.sharedInboxURL.appendingPathComponent("\(token).json")
        guard
            let data = try? Data(contentsOf: metaURL),
            let payload = try? JSONDecoder().decode(ShareImportPayload.self, from: data)
        else { return }
        let imageURL = AppGroup.sharedInboxURL.appendingPathComponent(payload.filename)
        guard
            let imageData = try? Data(contentsOf: imageURL),
            let image = UIImage(data: imageData)
        else { return }
        pendingImportImage = image

        // Clean up the handoff files now that we've consumed them.
        try? FileManager.default.removeItem(at: metaURL)
        try? FileManager.default.removeItem(at: imageURL)
    }

    func handleDroppedProviders(_ providers: [NSItemProvider]) {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: UIImage.self) }) else {
            return
        }
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            guard let image = object as? UIImage else { return }
            Task { @MainActor [weak self] in
                self?.pendingImportImage = image
            }
        }
    }

    // MARK: Puzzle lifecycle

    /// Build a puzzle on a background queue and persist metadata + source image.
    func createPuzzle(
        fromImage image: UIImage,
        title: String,
        difficulty: Difficulty,
        strategy: GridStrategy
    ) async -> PuzzleMetadata? {
        guard let rgb = image.rgbImage() else { return nil }
        let store = self.store

        let metadata: PuzzleMetadata? = await Task.detached(priority: .userInitiated) {
            let generated = PuzzleGenerator.generate(
                image: rgb,
                difficulty: difficulty,
                strategy: strategy
            )

            let metadata = PuzzleMetadata(
                title: title,
                difficulty: difficulty,
                strategy: strategy,
                workingWidth: generated.workingWidth,
                workingHeight: generated.workingHeight,
                palette: generated.palette,
                regions: generated.regions,
                sourceImageFilename: "source.png",
                regionMapFilename: "regionMap.png"
            )

            do {
                try store.saveMetadata(metadata)
                // Persist source image.
                if let pngData = image.pngData() {
                    let sourceURL = store.puzzleDirectory(id: metadata.id)
                        .appendingPathComponent(metadata.sourceImageFilename)
                    try pngData.write(to: sourceURL, options: .atomic)
                }
                // Persist a new empty progress.
                try store.saveProgress(PuzzleProgress(puzzleId: metadata.id))
                return metadata
            } catch {
                return nil
            }
        }.value

        reload()
        return metadata
    }

    func progress(for puzzleId: UUID) -> PuzzleProgress {
        (try? store.loadProgress(id: puzzleId)) ?? PuzzleProgress(puzzleId: puzzleId)
    }

    func save(progress: PuzzleProgress) {
        try? store.saveProgress(progress)
    }

    func deletePuzzle(_ id: UUID) {
        try? store.delete(id: id)
        reload()
    }
}
