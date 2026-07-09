import Foundation

/// Disk-backed store for puzzles. Each puzzle lives in its own folder under
/// `root/Puzzles/<uuid>/` and consists of:
///
/// - `metadata.json`  — `PuzzleMetadata`
/// - `progress.json`  — `PuzzleProgress`
/// - `source.png`     — original image (filename comes from metadata)
/// - `regionMap.pbnr` — lossless UInt32 region-id map
/// - `outline.png`    — optional outline overlay
///
/// The store is pure Foundation so it can be tested on Linux.
public final class PuzzleStore {
    public enum StoreError: Error {
        case puzzleNotFound(UUID)
        case unsupportedSchema(Int)
        case invalidMetadata(UUID)
    }

    public struct ListResult {
        public let puzzles: [PuzzleMetadata]
        public let quarantinedPuzzleCount: Int
    }

    public let rootDirectory: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(rootDirectory: URL, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager

        // Use Double seconds-since-1970 so round-trips of `Date()` compare
        // bit-for-bit equal. ISO-8601 string formatting drops sub-millisecond
        // precision and would make round-trip tests flaky.
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .secondsSince1970

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .secondsSince1970
    }

    public func puzzleDirectory(id: UUID) -> URL {
        rootDirectory
            .appendingPathComponent("Puzzles", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// Create the root + per-puzzle directories. Safe to call repeatedly.
    public func createPuzzleDirectory(id: UUID) throws -> URL {
        let dir = puzzleDirectory(id: id)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public func saveMetadata(_ metadata: PuzzleMetadata) throws {
        let dir = try createPuzzleDirectory(id: metadata.id)
        let url = dir.appendingPathComponent("metadata.json")
        let data = try encoder.encode(metadata)
        try data.write(to: url, options: .atomic)
    }

    public func loadMetadata(id: UUID) throws -> PuzzleMetadata {
        let url = puzzleDirectory(id: id).appendingPathComponent("metadata.json")
        guard fileManager.fileExists(atPath: url.path) else {
            throw StoreError.puzzleNotFound(id)
        }
        let data = try Data(contentsOf: url)
        let metadata = try decoder.decode(PuzzleMetadata.self, from: data)
        guard metadata.schemaVersion <= PuzzleMetadata.currentSchemaVersion else {
            throw StoreError.unsupportedSchema(metadata.schemaVersion)
        }
        guard isValid(metadata) else { throw StoreError.invalidMetadata(id) }
        return metadata
    }

    public func saveProgress(_ progress: PuzzleProgress) throws {
        let dir = try createPuzzleDirectory(id: progress.puzzleId)
        let url = dir.appendingPathComponent("progress.json")
        let data = try encoder.encode(progress)
        try data.write(to: url, options: .atomic)
    }

    public func loadProgress(id: UUID) throws -> PuzzleProgress {
        let url = puzzleDirectory(id: id).appendingPathComponent("progress.json")
        guard fileManager.fileExists(atPath: url.path) else {
            // No progress yet — return a fresh one.
            return PuzzleProgress(puzzleId: id)
        }
        let data = try Data(contentsOf: url)
        let progress = try decoder.decode(PuzzleProgress.self, from: data)
        guard progress.schemaVersion <= PuzzleProgress.currentSchemaVersion else {
            throw StoreError.unsupportedSchema(progress.schemaVersion)
        }
        return progress
    }

    /// Delete a puzzle and everything associated with it.
    public func delete(id: UUID) throws {
        let dir = puzzleDirectory(id: id)
        if fileManager.fileExists(atPath: dir.path) {
            try fileManager.removeItem(at: dir)
        }
    }

    /// Return the metadata of every stored puzzle, newest first.
    public func listPuzzles() throws -> [PuzzleMetadata] {
        try listPuzzlesWithRecovery().puzzles
    }

    /// Loads every healthy puzzle while isolating malformed folders. The
    /// recovery count lets the app explain why an item disappeared instead of
    /// silently swallowing storage damage.
    public func listPuzzlesWithRecovery() throws -> ListResult {
        let puzzlesRoot = rootDirectory.appendingPathComponent("Puzzles", isDirectory: true)
        guard fileManager.fileExists(atPath: puzzlesRoot.path) else {
            return ListResult(puzzles: [], quarantinedPuzzleCount: 0)
        }
        let contents = try fileManager.contentsOfDirectory(
            at: puzzlesRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        var metadatas: [PuzzleMetadata] = []
        var quarantinedCount = 0
        for dir in contents {
            let metaURL = dir.appendingPathComponent("metadata.json")
            guard fileManager.fileExists(atPath: metaURL.path) else { continue }
            let data = try Data(contentsOf: metaURL)
            do {
                let meta = try decoder.decode(PuzzleMetadata.self, from: data)
                guard meta.schemaVersion <= PuzzleMetadata.currentSchemaVersion, isValid(meta) else {
                    throw StoreError.invalidMetadata(meta.id)
                }
                metadatas.append(meta)
            } catch {
                var quarantine = dir.appendingPathExtension("corrupt")
                if fileManager.fileExists(atPath: quarantine.path) {
                    quarantine = dir
                        .deletingLastPathComponent()
                        .appendingPathComponent("\(dir.lastPathComponent).corrupt-\(UUID().uuidString)")
                }
                try fileManager.moveItem(at: dir, to: quarantine)
                quarantinedCount += 1
            }
        }
        metadatas.sort { $0.lastEditedAt > $1.lastEditedAt }
        return ListResult(puzzles: metadatas, quarantinedPuzzleCount: quarantinedCount)
    }

    private func isValid(_ metadata: PuzzleMetadata) -> Bool {
        guard metadata.workingWidth > 0, metadata.workingHeight > 0,
              metadata.sourcePixelWidth > 0, metadata.sourcePixelHeight > 0,
              ShareImport.isSafeFilename(metadata.sourceImageFilename),
              ShareImport.isSafeFilename(metadata.regionMapFilename),
              metadata.outlineFilename.map(ShareImport.isSafeFilename) ?? true else {
            return false
        }
        let ids = metadata.regions.map(\.id)
        guard Set(ids).count == ids.count else { return false }
        return metadata.regions.allSatisfy { region in
            region.id >= 0 &&
            region.pixelCount > 0 &&
            metadata.palette.colors.indices.contains(region.colorIndex) &&
            region.bounds.minX >= 0 &&
            region.bounds.minY >= 0 &&
            region.bounds.maxX < metadata.workingWidth &&
            region.bounds.maxY < metadata.workingHeight &&
            region.bounds.minX <= region.bounds.maxX &&
            region.bounds.minY <= region.bounds.maxY
        }
    }
}
