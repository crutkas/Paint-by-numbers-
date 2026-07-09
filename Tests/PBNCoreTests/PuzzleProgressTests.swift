import XCTest
@testable import PBNCore

final class PuzzleProgressTests: XCTestCase {
    private func makePuzzle(regionCount: Int) -> PuzzleMetadata {
        let palette = ColorPalette(colors: [RGBColor(r: 0, g: 0, b: 0)])
        let regions = (0..<regionCount).map { id in
            PuzzleRegion(
                id: id,
                colorIndex: 0,
                pixelCount: 10,
                bounds: PixelRect(minX: 0, minY: 0, maxX: 1, maxY: 1),
                centroid: PixelPoint(x: 0, y: 0)
            )
        }
        return PuzzleMetadata(
            title: "Test",
            difficulty: .medium,
            strategy: .freeformRegions,
            workingWidth: 10,
            workingHeight: 10,
            palette: palette,
            regions: regions,
            sourceImageFilename: "source.png",
            regionMapFilename: "regionMap.png"
        )
    }

    // A newly opened puzzle must start at zero and never trigger completion.
    func testCompletionIsZeroForNewProgress() {
        let puzzle = makePuzzle(regionCount: 10)
        let progress = PuzzleProgress(puzzleId: puzzle.id)
        XCTAssertEqual(
            PuzzleProgressCalculator.completion(progress: progress, puzzle: puzzle),
            0.0
        )
        XCTAssertFalse(PuzzleProgressCalculator.isComplete(progress: progress, puzzle: puzzle))
    }

    // Filling every valid region is the sole condition that should complete a puzzle.
    func testCompletionIsOneWhenAllRegionsFilled() {
        let puzzle = makePuzzle(regionCount: 4)
        var progress = PuzzleProgress(puzzleId: puzzle.id)
        progress.filledRegionIds = Set(puzzle.regions.map { $0.id })
        XCTAssertEqual(
            PuzzleProgressCalculator.completion(progress: progress, puzzle: puzzle),
            1.0
        )
        XCTAssertTrue(PuzzleProgressCalculator.isComplete(progress: progress, puzzle: puzzle))
    }

    // Corrupt extra IDs must not produce percentages above the user-facing range.
    func testCompletionIsClampedForExtraRegionIds() {
        let puzzle = makePuzzle(regionCount: 3)
        var progress = PuzzleProgress(puzzleId: puzzle.id)
        progress.filledRegionIds = Set([0, 1, 2, 99])
        let c = PuzzleProgressCalculator.completion(progress: progress, puzzle: puzzle)
        XCTAssertLessThanOrEqual(c, 1.0)
    }

    // Empty malformed puzzles must avoid NaN and must not count as completed.
    func testCompletionHandlesEmptyPuzzle() {
        let puzzle = makePuzzle(regionCount: 0)
        let progress = PuzzleProgress(puzzleId: puzzle.id)
        XCTAssertEqual(
            PuzzleProgressCalculator.completion(progress: progress, puzzle: puzzle),
            0.0
        )
        XCTAssertFalse(PuzzleProgressCalculator.isComplete(progress: progress, puzzle: puzzle))
    }

    // Palette counts and hints depend on excluding filled regions of only the requested color.
    func testRemainingRegionIdsFiltersFilledAndColor() {
        let palette = ColorPalette(colors: [
            RGBColor(r: 0, g: 0, b: 0),
            RGBColor(r: 255, g: 255, b: 255)
        ])
        let regions = [
            PuzzleRegion(id: 0, colorIndex: 0, pixelCount: 1,
                         bounds: PixelRect(minX: 0, minY: 0, maxX: 0, maxY: 0),
                         centroid: PixelPoint(x: 0, y: 0)),
            PuzzleRegion(id: 1, colorIndex: 1, pixelCount: 1,
                         bounds: PixelRect(minX: 0, minY: 0, maxX: 0, maxY: 0),
                         centroid: PixelPoint(x: 0, y: 0)),
            PuzzleRegion(id: 2, colorIndex: 0, pixelCount: 1,
                         bounds: PixelRect(minX: 0, minY: 0, maxX: 0, maxY: 0),
                         centroid: PixelPoint(x: 0, y: 0))
        ]
        let puzzle = PuzzleMetadata(
            title: "x",
            difficulty: .easy,
            strategy: .freeformRegions,
            workingWidth: 1,
            workingHeight: 1,
            palette: palette,
            regions: regions,
            sourceImageFilename: "s.png",
            regionMapFilename: "r.png"
        )
        var progress = PuzzleProgress(puzzleId: puzzle.id)
        progress.filledRegionIds = [0]
        let remaining0 = PuzzleProgressCalculator.remainingRegionIds(
            forColor: 0, puzzle: puzzle, progress: progress
        )
        XCTAssertEqual(remaining0, [2])
        let remaining1 = PuzzleProgressCalculator.remainingRegionIds(
            forColor: 1, puzzle: puzzle, progress: progress
        )
        XCTAssertEqual(remaining1, [1])
    }

    // A damaged progress file may contain plausible but nonexistent IDs; they
    // must not inflate completion or unlock the completion celebration.
    func testUnknownRegionIdsDoNotCountTowardCompletion() {
        let puzzle = makePuzzle(regionCount: 2)
        let progress = PuzzleProgress(puzzleId: puzzle.id, filledRegionIds: [999, 1])

        XCTAssertEqual(PuzzleProgressCalculator.completion(progress: progress, puzzle: puzzle), 0.5)
        XCTAssertFalse(PuzzleProgressCalculator.isComplete(progress: progress, puzzle: puzzle))
        XCTAssertEqual(
            progress.sanitized(validRegionIds: Set(puzzle.regions.map(\.id))).filledRegionIds,
            [1]
        )
    }

    // A progress file copied into the wrong puzzle folder must never unlock or
    // alter that puzzle, even when its numeric region IDs happen to overlap.
    func testProgressForDifferentPuzzleIsIgnored() {
        let puzzle = makePuzzle(regionCount: 1)
        let foreign = PuzzleProgress(puzzleId: UUID(), filledRegionIds: [0])

        XCTAssertEqual(PuzzleProgressCalculator.completion(progress: foreign, puzzle: puzzle), 0)
        XCTAssertFalse(PuzzleProgressCalculator.isComplete(progress: foreign, puzzle: puzzle))
        XCTAssertEqual(
            PuzzleProgressCalculator.remainingRegionIds(forColor: 0, puzzle: puzzle, progress: foreign),
            [0]
        )
    }
}
