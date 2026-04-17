import XCTest
@testable import PBNCore

final class KMeansQuantizerTests: XCTestCase {
    private func makeStripedImage() -> RGBImage {
        // 10x10 image: left half red, right half blue.
        var pixels: [RGBColor] = []
        for _ in 0..<10 {
            for x in 0..<10 {
                pixels.append(x < 5 ? RGBColor(r: 250, g: 10, b: 10) : RGBColor(r: 10, g: 10, b: 250))
            }
        }
        return RGBImage(width: 10, height: 10, pixels: pixels)
    }

    func testQuantizeTwoClusterImageYieldsExactlyTwoColors() {
        let img = makeStripedImage()
        let (palette, labels) = KMeansQuantizer.quantize(image: img, k: 2)
        XCTAssertEqual(palette.colors.count, 2)
        XCTAssertEqual(labels.count, img.pixels.count)

        // All pixels on the left should share one label; all on the right another.
        let leftLabels = Set((0..<10).flatMap { y in (0..<5).map { x in labels[y * 10 + x] } })
        let rightLabels = Set((0..<10).flatMap { y in (5..<10).map { x in labels[y * 10 + x] } })
        XCTAssertEqual(leftLabels.count, 1)
        XCTAssertEqual(rightLabels.count, 1)
        XCTAssertNotEqual(leftLabels, rightLabels)
    }

    func testQuantizeIsDeterministicForSameSeed() {
        let img = makeStripedImage()
        let a = KMeansQuantizer.quantize(image: img, k: 2, seed: 42)
        let b = KMeansQuantizer.quantize(image: img, k: 2, seed: 42)
        XCTAssertEqual(a.palette, b.palette)
        XCTAssertEqual(a.labels, b.labels)
    }

    func testPaletteIsSortedByLuminance() {
        // Three distinct colors at very different luminance levels.
        var pixels: [RGBColor] = []
        let dark = RGBColor(r: 10, g: 10, b: 10)
        let mid = RGBColor(r: 128, g: 128, b: 128)
        let light = RGBColor(r: 245, g: 245, b: 245)
        for c in [dark, mid, light] {
            for _ in 0..<20 { pixels.append(c) }
        }
        let img = RGBImage(width: 10, height: 6, pixels: pixels)
        let (palette, _) = KMeansQuantizer.quantize(image: img, k: 3)
        XCTAssertEqual(palette.colors.count, 3)
        for i in 1..<palette.colors.count {
            XCTAssertLessThanOrEqual(palette.colors[i - 1].luminance, palette.colors[i].luminance)
        }
    }

    func testQuantizeHandlesKGreaterThanPixels() {
        let img = RGBImage(width: 1, height: 1, pixels: [RGBColor(r: 100, g: 100, b: 100)])
        let (palette, labels) = KMeansQuantizer.quantize(image: img, k: 10)
        XCTAssertEqual(palette.colors.count, 1)
        XCTAssertEqual(labels, [0])
    }

    func testQuantizeEmptyImage() {
        let img = RGBImage(width: 0, height: 0, pixels: [])
        let (palette, labels) = KMeansQuantizer.quantize(image: img, k: 5)
        XCTAssertTrue(palette.colors.isEmpty)
        XCTAssertTrue(labels.isEmpty)
    }
}
