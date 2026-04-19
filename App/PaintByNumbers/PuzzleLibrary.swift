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
        // `ShareImport.token(from:)` applies a strict allowlist (UUID-safe
        // characters only), so the returned token is safe to use as a path
        // component. Re-validating here defensively rejects any token that
        // might have been obtained through another code path.
        guard let token = ShareImport.token(from: url), ShareImport.isValidToken(token) else {
            return
        }
        // Look up the token's metadata and image in the shared inbox.
        let metaURL = AppGroup.sharedInboxURL.appendingPathComponent("\(token).json")
        guard
            let data = try? Data(contentsOf: metaURL),
            let payload = try? JSONDecoder().decode(ShareImportPayload.self, from: data),
            ShareImport.isValidToken(payload.token)
        else { return }
        // The payload's filename is controlled by the Share Extension we ship,
        // but re-check it's not trying to escape the shared inbox folder.
        let imageURL = AppGroup.sharedInboxURL.appendingPathComponent(payload.filename)
        let inboxPath = AppGroup.sharedInboxURL.standardizedFileURL.path
        guard imageURL.standardizedFileURL.path.hasPrefix(inboxPath) else { return }
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

    /// Build a puzzle on a background queue and persist metadata + source
    /// image + region-map PNG.
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
        guard let rgb = image.rgbImage() else { return nil }

        // 1. Expensive, side-effect-free work on a background thread.
        let result: (generated: PuzzleGenerator.GeneratedPuzzle, sourcePNG: Data?, regionPNG: Data?) =
            await Task.detached(priority: .userInitiated) {
                let generated = PuzzleGenerator.generate(
                    image: rgb,
                    difficulty: difficulty,
                    strategy: strategy
                )
                let sourcePNG = image.pngData()
                let regionPNG = Self.encodeRegionMap(
                    regionIds: generated.regionIds,
                    width: generated.workingWidth,
                    height: generated.workingHeight
                )
                return (generated, sourcePNG, regionPNG)
            }.value

        // 2. All persistence back on the main actor, using the single shared
        //    `PuzzleStore`. This prevents racing `JSONEncoder`/`JSONDecoder`.
        let generated = result.generated
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
            let dir = store.puzzleDirectory(id: metadata.id)
            if let sourcePNG = result.sourcePNG {
                try sourcePNG.write(
                    to: dir.appendingPathComponent(metadata.sourceImageFilename),
                    options: .atomic
                )
            }
            if let regionPNG = result.regionPNG {
                try regionPNG.write(
                    to: dir.appendingPathComponent(metadata.regionMapFilename),
                    options: .atomic
                )
            }
            try store.saveProgress(PuzzleProgress(puzzleId: metadata.id))
        } catch {
            // If any file failed to write, roll back so we never leave a
            // partial puzzle whose metadata references missing blobs.
            try? store.delete(id: metadata.id)
            reload()
            return nil
        }
        reload()
        return metadata
    }

    /// Encode the per-pixel region-id map as an 8-bit grayscale PNG. Each
    /// pixel stores `regionId % 256`; for puzzles with more than 256 regions
    /// the caller should still treat this as a debug artifact — the
    /// authoritative region list lives in `metadata.regions`.
    nonisolated private static func encodeRegionMap(regionIds: [Int], width: Int, height: Int) -> Data? {
        guard width > 0, height > 0, regionIds.count == width * height else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bytesPerRow = width
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        for i in 0..<regionIds.count {
            bytes[i] = UInt8(truncatingIfNeeded: max(0, regionIds[i]))
        }
        let ctx = bytes.withUnsafeMutableBytes { buf -> CGContext? in
            CGContext(
                data: buf.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            )
        }
        guard let cg = ctx?.makeImage() else { return nil }
        return UIImage(cgImage: cg).pngData()
    }

    func progress(for puzzleId: UUID) -> PuzzleProgress {
        (try? store.loadProgress(id: puzzleId)) ?? PuzzleProgress(puzzleId: puzzleId)
    }

    func save(progress: PuzzleProgress) {
        try? store.saveProgress(progress)
        // Notify observers (e.g. library tiles showing completion %) so
        // they re-render with the latest progress when the player returns
        // to the home screen after painting.
        objectWillChange.send()
    }

    func deletePuzzle(_ id: UUID) {
        try? store.delete(id: id)
        reload()
    }
}
