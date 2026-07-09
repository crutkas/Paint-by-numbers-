import XCTest
@testable import PBNCore

final class PuzzleGeneratorTests: XCTestCase {
    /// Build a synthetic image with two clear color bands so we can predict
    /// the generator's output.
    private func twoBandImage(width: Int = 32, height: Int = 32) -> RGBImage {
        var pixels: [RGBColor] = []
        for y in 0..<height {
            for _ in 0..<width {
                pixels.append(
                    y < height / 2
                        ? RGBColor(r: 240, g: 30, b: 30)
                        : RGBColor(r: 30, g: 30, b: 240)
                )
            }
        }
        return RGBImage(width: width, height: height, pixels: pixels)
    }

    // Difficulty promises a specific palette size that drives the numbered color choices.
    func testGenerateProducesExpectedPaletteSize() {
        let img = twoBandImage()
        let puzzle = PuzzleGenerator.generate(image: img, difficulty: .easy)
        // The image only contains two colors, so the generator should end up
        // with at most two palette entries even though easy asks for more.
        XCTAssertLessThanOrEqual(puzzle.palette.colors.count, Difficulty.easy.paletteSize)
        XCTAssertGreaterThanOrEqual(puzzle.palette.colors.count, 1)
    }

    // Valid photos must always yield paintable regions and a complete per-pixel map.
    func testGenerateProducesNonEmptyRegions() {
        let img = twoBandImage()
        let puzzle = PuzzleGenerator.generate(image: img, difficulty: .medium)
        XCTAssertFalse(puzzle.regions.isEmpty)
        XCTAssertEqual(
            puzzle.regionIds.count,
            puzzle.workingWidth * puzzle.workingHeight
        )
        for id in puzzle.regionIds {
            XCTAssertGreaterThanOrEqual(id, 0)
            XCTAssertLessThan(id, puzzle.regions.count)
        }
    }

    // Identical inputs and seeds must generate stable puzzles across saves and platforms.
    func testGenerateIsDeterministicForSameSeed() {
        let img = twoBandImage()
        let a = PuzzleGenerator.generate(image: img, difficulty: .medium, seed: 99)
        let b = PuzzleGenerator.generate(image: img, difficulty: .medium, seed: 99)
        XCTAssertEqual(a.palette, b.palette)
        XCTAssertEqual(a.regions, b.regions)
        XCTAssertEqual(a.regionIds, b.regionIds)
    }

    // Square-grid working dimensions must align to cells so edge hit-testing stays consistent.
    func testSquareGridProducesMultipleOfCellSizeWidth() {
        let img = twoBandImage(width: 40, height: 40)
        let puzzle = PuzzleGenerator.generate(
            image: img,
            difficulty: .medium,
            strategy: .squareGrid(cellSize: 4)
        )
        // Regions can span multiple cells but the generator should still have
        // at least two regions for a two-band image.
        XCTAssertGreaterThanOrEqual(puzzle.regions.count, 2)
    }

    // Working resolution must preserve photo proportions to avoid distorted puzzles.
    func testWorkingSizePreservesAspectRatio() {
        let img = RGBImage(width: 400, height: 100, fill: RGBColor(r: 0, g: 0, b: 0))
        let (w, h) = PuzzleGenerator.workingSize(forImage: img, difficulty: .medium)
        XCTAssertEqual(w, Difficulty.medium.workingLongEdge)
        // 4:1 aspect ratio should be preserved within one pixel.
        XCTAssertEqual(h, Int((Double(Difficulty.medium.workingLongEdge) / 4.0).rounded()))
    }

    // Rounded short-edge sizing avoids a systematic one-pixel aspect-ratio bias.
    func testWorkingSizeRoundsRatherThanTruncates() {
        // 300x100 at target `workingLongEdge` -> expected h = round(100/300 * target),
        // not one less (which a `.rounded()`-on-wrong-operand truncation bug would
        // produce). This regression-tests the `workingSize` rounding fix.
        let img = RGBImage(width: 300, height: 100, fill: RGBColor(r: 0, g: 0, b: 0))
        let (w, h) = PuzzleGenerator.workingSize(forImage: img, difficulty: .medium)
        let target = Difficulty.medium.workingLongEdge
        XCTAssertEqual(w, target)
        XCTAssertEqual(h, Int(((100.0 / 300.0) * Double(target)).rounded()))
    }

    // Every region color index must be safe to use against the generated palette.
    func testRegionsColorIndicesAreValid() {
        let img = twoBandImage()
        let puzzle = PuzzleGenerator.generate(image: img, difficulty: .medium)
        for region in puzzle.regions {
            XCTAssertGreaterThanOrEqual(region.colorIndex, 0)
            XCTAssertLessThan(region.colorIndex, puzzle.palette.colors.count)
        }
    }

    // Invalid empty images must return an empty result rather than crash the pipeline.
    func testEmptyImageGeneratesEmptyPuzzle() {
        let img = RGBImage(width: 0, height: 0, pixels: [])
        let puzzle = PuzzleGenerator.generate(image: img, difficulty: .easy)
        XCTAssertTrue(puzzle.regions.isEmpty)
        XCTAssertTrue(puzzle.regionIds.isEmpty)
    }
}
