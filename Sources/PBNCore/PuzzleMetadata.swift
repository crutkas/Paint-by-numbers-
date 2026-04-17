import Foundation

/// Persistable metadata for a saved puzzle. Large binary blobs (source image,
/// region-id map PNG, outline PNG) are stored as files on disk and referenced
/// by path; only the metadata lives in this struct (or, on device, SwiftData).
public struct PuzzleMetadata: Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var createdAt: Date
    public var lastEditedAt: Date
    public var difficulty: Difficulty
    public var strategy: GridStrategy
    public var workingWidth: Int
    public var workingHeight: Int
    public var palette: ColorPalette
    public var regions: [PuzzleRegion]
    /// Filename (relative to the puzzle folder) for the original source image.
    public var sourceImageFilename: String
    /// Filename for the region-id map image (one pixel per working pixel).
    public var regionMapFilename: String
    /// Optional filename for a pre-rendered outline overlay.
    public var outlineFilename: String?

    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        lastEditedAt: Date = Date(),
        difficulty: Difficulty,
        strategy: GridStrategy,
        workingWidth: Int,
        workingHeight: Int,
        palette: ColorPalette,
        regions: [PuzzleRegion],
        sourceImageFilename: String,
        regionMapFilename: String,
        outlineFilename: String? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.lastEditedAt = lastEditedAt
        self.difficulty = difficulty
        self.strategy = strategy
        self.workingWidth = workingWidth
        self.workingHeight = workingHeight
        self.palette = palette
        self.regions = regions
        self.sourceImageFilename = sourceImageFilename
        self.regionMapFilename = regionMapFilename
        self.outlineFilename = outlineFilename
    }
}

/// Mutable progress state for a puzzle. `filledRegionIds` is the set of region
/// ids the user has completed.
public struct PuzzleProgress: Codable, Equatable, Sendable {
    public var puzzleId: UUID
    public var filledRegionIds: Set<Int>
    public var lastEditedAt: Date

    public init(
        puzzleId: UUID,
        filledRegionIds: Set<Int> = [],
        lastEditedAt: Date = Date()
    ) {
        self.puzzleId = puzzleId
        self.filledRegionIds = filledRegionIds
        self.lastEditedAt = lastEditedAt
    }

    /// Completion ratio in `0...1` given the puzzle's region list. Returns
    /// `0` for empty puzzles rather than NaN to keep UI code simple.
    public func completion(totalRegions: Int) -> Double {
        guard totalRegions > 0 else { return 0 }
        return min(1.0, Double(filledRegionIds.count) / Double(totalRegions))
    }

    public var isComplete: Bool {
        // `isComplete` is evaluated against the puzzle's region count by
        // `PuzzleProgressCalculator`; convenience bool here is based on an
        // externally-tracked count held by the caller.
        return false
    }
}

/// Utility helpers for progress calculation. Separated out so the logic is
/// trivially testable (no file I/O, no UIKit).
public enum PuzzleProgressCalculator {
    public static func completion(progress: PuzzleProgress, puzzle: PuzzleMetadata) -> Double {
        progress.completion(totalRegions: puzzle.regions.count)
    }

    public static func isComplete(progress: PuzzleProgress, puzzle: PuzzleMetadata) -> Bool {
        !puzzle.regions.isEmpty && progress.filledRegionIds.count >= puzzle.regions.count
    }

    /// Returns the set of region ids belonging to `colorIndex` that have not
    /// been filled yet. Used to power "Hint" and "Next of this color" buttons.
    public static func remainingRegionIds(
        forColor colorIndex: Int,
        puzzle: PuzzleMetadata,
        progress: PuzzleProgress
    ) -> [Int] {
        puzzle.regions
            .filter { $0.colorIndex == colorIndex && !progress.filledRegionIds.contains($0.id) }
            .map { $0.id }
    }
}
