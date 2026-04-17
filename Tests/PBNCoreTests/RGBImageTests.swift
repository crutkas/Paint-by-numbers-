import XCTest
@testable import PBNCore

final class RGBImageTests: XCTestCase {
    func testSubscriptRoundTrip() {
        var img = RGBImage(width: 2, height: 2, fill: RGBColor(r: 0, g: 0, b: 0))
        img[0, 0] = RGBColor(r: 1, g: 2, b: 3)
        img[1, 1] = RGBColor(r: 4, g: 5, b: 6)
        XCTAssertEqual(img[0, 0], RGBColor(r: 1, g: 2, b: 3))
        XCTAssertEqual(img[1, 1], RGBColor(r: 4, g: 5, b: 6))
        XCTAssertEqual(img[0, 1], RGBColor(r: 0, g: 0, b: 0))
    }

    func testScalingToSameSizeReturnsEqual() {
        let img = RGBImage(width: 3, height: 3, fill: RGBColor(r: 10, g: 20, b: 30))
        let scaled = img.nearestNeighborScaled(toWidth: 3, height: 3)
        XCTAssertEqual(scaled, img)
    }

    func testScalingDownPreservesCorners() {
        let red = RGBColor(r: 255, g: 0, b: 0)
        let blue = RGBColor(r: 0, g: 0, b: 255)
        // 2x2 image: top-left red, bottom-right blue, others green/white
        let pixels: [RGBColor] = [
            red, RGBColor(r: 0, g: 255, b: 0),
            RGBColor(r: 255, g: 255, b: 255), blue
        ]
        let img = RGBImage(width: 2, height: 2, pixels: pixels)
        let scaled = img.nearestNeighborScaled(toWidth: 2, height: 2)
        XCTAssertEqual(scaled[0, 0], red)
        XCTAssertEqual(scaled[1, 1], blue)
    }

    func testScalingUpDoesNotInventColors() {
        let pixels: [RGBColor] = [
            RGBColor(r: 255, g: 0, b: 0),
            RGBColor(r: 0, g: 0, b: 255)
        ]
        let img = RGBImage(width: 2, height: 1, pixels: pixels)
        let scaled = img.nearestNeighborScaled(toWidth: 4, height: 1)
        let uniqueColors = Set(scaled.pixels)
        XCTAssertEqual(uniqueColors, Set(pixels))
    }
}
