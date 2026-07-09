import Foundation

/// Persistable metadata for a saved puzzle. Large binary blobs (source image,
/// region-id map PNG, outline PNG) are stored as files on disk and referenced
/// by path; only lightweight metadata lives in this struct.
public struct PuzzleMetadata: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2
    public var schemaVersion: Int
    public let id: UUID
    public var title: String
    public var createdAt: Date
    public var lastEditedAt: Date
    public var difficulty: Difficulty
    public var strategy: GridStrategy
    public var workingWidth: Int
    public var workingHeight: Int
    /// Original image dimensions in pixels, used for full-resolution export.
    public var sourcePixelWidth: Int
    public var sourcePixelHeight: Int
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
        sourcePixelWidth: Int? = nil,
        sourcePixelHeight: Int? = nil,
        palette: ColorPalette,
        regions: [PuzzleRegion],
        sourceImageFilename: String,
        regionMapFilename: String,
        outlineFilename: String? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.lastEditedAt = lastEditedAt
        self.difficulty = difficulty
        self.strategy = strategy
        self.workingWidth = workingWidth
        self.workingHeight = workingHeight
        self.sourcePixelWidth = sourcePixelWidth ?? workingWidth
        self.sourcePixelHeight = sourcePixelHeight ?? workingHeight
        self.palette = palette
        self.regions = regions
        self.sourceImageFilename = sourceImageFilename
        self.regionMapFilename = regionMapFilename
        self.outlineFilename = outlineFilename
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, title, createdAt, lastEditedAt, difficulty, strategy
        case workingWidth, workingHeight, sourcePixelWidth, sourcePixelHeight
        case palette, regions, sourceImageFilename, regionMapFilename, outlineFilename
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard decodedVersion <= Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: values,
                debugDescription: "Unsupported puzzle schema \(decodedVersion)"
            )
        }
        schemaVersion = Self.currentSchemaVersion
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        lastEditedAt = try values.decode(Date.self, forKey: .lastEditedAt)
        difficulty = try values.decode(Difficulty.self, forKey: .difficulty)
        strategy = try values.decode(GridStrategy.self, forKey: .strategy)
        workingWidth = try values.decode(Int.self, forKey: .workingWidth)
        workingHeight = try values.decode(Int.self, forKey: .workingHeight)
        sourcePixelWidth = try values.decodeIfPresent(Int.self, forKey: .sourcePixelWidth) ?? workingWidth
        sourcePixelHeight = try values.decodeIfPresent(Int.self, forKey: .sourcePixelHeight) ?? workingHeight
        palette = try values.decode(ColorPalette.self, forKey: .palette)
        regions = try values.decode([PuzzleRegion].self, forKey: .regions)
        sourceImageFilename = try values.decode(String.self, forKey: .sourceImageFilename)
        regionMapFilename = try values.decode(String.self, forKey: .regionMapFilename)
        outlineFilename = try values.decodeIfPresent(String.self, forKey: .outlineFilename)
    }
}

/// Mutable progress state for a puzzle. `filledRegionIds` is the set of region
/// ids the user has completed.
public struct PuzzleProgress: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2
    public var schemaVersion: Int
    public var puzzleId: UUID
    public var filledRegionIds: Set<Int>
    public var lastEditedAt: Date

    public init(
        puzzleId: UUID,
        filledRegionIds: Set<Int> = [],
        lastEditedAt: Date = Date()
    ) {
        self.schemaVersion = Self.currentSchemaVersion
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

    /// Removes IDs that are not present in the puzzle, repairing stale or
    /// corrupted progress before it is displayed or saved.
    public func sanitized(validRegionIds: Set<Int>) -> PuzzleProgress {
        PuzzleProgress(
            puzzleId: puzzleId,
            filledRegionIds: filledRegionIds.intersection(validRegionIds),
            lastEditedAt: lastEditedAt
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, puzzleId, filledRegionIds, lastEditedAt
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard decodedVersion <= Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: values,
                debugDescription: "Unsupported progress schema \(decodedVersion)"
            )
        }
        schemaVersion = Self.currentSchemaVersion
        puzzleId = try values.decode(UUID.self, forKey: .puzzleId)
        filledRegionIds = try values.decode(Set<Int>.self, forKey: .filledRegionIds)
        lastEditedAt = try values.decode(Date.self, forKey: .lastEditedAt)
    }
}

/// Utility helpers for progress calculation. Separated out so the logic is
/// trivially testable (no file I/O, no UIKit).
public enum PuzzleProgressCalculator {
    public static func completion(progress: PuzzleProgress, puzzle: PuzzleMetadata) -> Double {
        let valid = Set(puzzle.regions.map(\.id))
        return progress.sanitized(validRegionIds: valid).completion(totalRegions: valid.count)
    }

    public static func isComplete(progress: PuzzleProgress, puzzle: PuzzleMetadata) -> Bool {
        let valid = Set(puzzle.regions.map(\.id))
        return !valid.isEmpty && progress.filledRegionIds.isSuperset(of: valid)
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
