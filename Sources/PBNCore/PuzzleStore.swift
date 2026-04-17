import Foundation

/// Disk-backed store for puzzles. Each puzzle lives in its own folder under
/// `root/Puzzles/<uuid>/` and consists of:
///
/// - `metadata.json`  — `PuzzleMetadata`
/// - `progress.json`  — `PuzzleProgress`
/// - `source.png`     — original image (filename comes from metadata)
/// - `regionMap.png`  — region-id map (filename comes from metadata)
/// - `outline.png`    — optional outline overlay
///
/// This layout mirrors the plan's "large blobs as files, metadata in
/// SwiftData" goal. The store itself is pure-Foundation so it tests on Linux;
/// on-device the iOS app wraps it with SwiftData for indexing + iCloud sync.
public final class PuzzleStore {
    public enum StoreError: Error {
        case puzzleNotFound(UUID)
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
        return try decoder.decode(PuzzleMetadata.self, from: data)
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
        return try decoder.decode(PuzzleProgress.self, from: data)
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
        let puzzlesRoot = rootDirectory.appendingPathComponent("Puzzles", isDirectory: true)
        guard fileManager.fileExists(atPath: puzzlesRoot.path) else { return [] }
        let contents = try fileManager.contentsOfDirectory(
            at: puzzlesRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        var metadatas: [PuzzleMetadata] = []
        for dir in contents {
            let metaURL = dir.appendingPathComponent("metadata.json")
            guard fileManager.fileExists(atPath: metaURL.path) else { continue }
            let data = try Data(contentsOf: metaURL)
            if let meta = try? decoder.decode(PuzzleMetadata.self, from: data) {
                metadatas.append(meta)
            }
        }
        metadatas.sort { $0.lastEditedAt > $1.lastEditedAt }
        return metadatas
    }
}
