import XCTest
@testable import PBNCore

final class PuzzleBrushTests: XCTestCase {
    private func makePuzzle() -> PuzzleMetadata {
        let palette = ColorPalette(colors: [
            RGBColor(r: 255, g: 0, b: 0),
            RGBColor(r: 0, g: 255, b: 0)
        ])
        let regions = [
            PuzzleRegion(
                id: 0,
                colorIndex: 0,
                pixelCount: 9,
                bounds: PixelRect(minX: 0, minY: 0, maxX: 2, maxY: 2),
                centroid: PixelPoint(x: 1, y: 1)
            ),
            PuzzleRegion(
                id: 1,
                colorIndex: 1,
                pixelCount: 9,
                bounds: PixelRect(minX: 3, minY: 0, maxX: 5, maxY: 2),
                centroid: PixelPoint(x: 4, y: 1)
            ),
            PuzzleRegion(
                id: 2,
                colorIndex: 0,
                pixelCount: 9,
                bounds: PixelRect(minX: 0, minY: 3, maxX: 2, maxY: 5),
                centroid: PixelPoint(x: 1, y: 4)
            ),
            PuzzleRegion(
                id: 3,
                colorIndex: 1,
                pixelCount: 9,
                bounds: PixelRect(minX: 3, minY: 3, maxX: 5, maxY: 5),
                centroid: PixelPoint(x: 4, y: 4)
            )
        ]
        return PuzzleMetadata(
            title: "Brush",
            difficulty: .easy,
            strategy: .squareGrid(cellSize: 3),
            workingWidth: 6,
            workingHeight: 6,
            palette: palette,
            regions: regions,
            sourceImageFilename: "source.png",
            regionMapFilename: "regionMap.png"
        )
    }

    func testDefaultBrushOnlyTargetsContainingRegion() {
        // WHY: the normal brush must stay precise so a regular tap still fills
        // exactly one square instead of unexpectedly spilling into neighbors.
        let puzzle = makePuzzle()

        XCTAssertEqual(
            PuzzleBrush.regionIds(
                around: PixelPoint(x: 1, y: 1),
                in: puzzle
            ),
            [0]
        )
    }

    func testLargeBrushIncludesAdjacentRegionsInDistanceOrder() {
        // WHY: the larger-brush accessibility setting is only useful if one
        // swipe can pick up the nearby cells around a kid's finger.
        let puzzle = makePuzzle()

        XCTAssertEqual(
            PuzzleBrush.regionIds(
                around: PixelPoint(x: 1, y: 1),
                brushRadius: 2,
                in: puzzle
            ),
            [0, 1, 2]
        )
    }

    func testLargeBrushStillExcludesFarAwayRegions() {
        // WHY: even with the larger brush enabled, painting one corner of the
        // puzzle must not accidentally jump across the board.
        let puzzle = makePuzzle()

        XCTAssertEqual(
            PuzzleBrush.regionIds(
                around: PixelPoint(x: 1, y: 1),
                brushRadius: 1,
                in: puzzle
            ),
            [0]
        )
    }
}
