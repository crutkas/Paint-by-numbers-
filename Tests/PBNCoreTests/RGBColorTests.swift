import XCTest
@testable import PBNCore

final class RGBColorTests: XCTestCase {
    func testClampingInit() {
        let c = RGBColor(ri: -5, gi: 300, bi: 128)
        XCTAssertEqual(c.r, 0)
        XCTAssertEqual(c.g, 255)
        XCTAssertEqual(c.b, 128)
    }

    func testSquaredDistanceIsSymmetric() {
        let a = RGBColor(r: 10, g: 20, b: 30)
        let b = RGBColor(r: 40, g: 60, b: 80)
        XCTAssertEqual(a.squaredDistance(to: b), b.squaredDistance(to: a))
    }

    func testSquaredDistanceValue() {
        let a = RGBColor(r: 0, g: 0, b: 0)
        let b = RGBColor(r: 3, g: 4, b: 0)
        // 3^2 + 4^2 + 0 = 25
        XCTAssertEqual(a.squaredDistance(to: b), 25)
    }

    func testLuminanceBoundsAndOrdering() {
        let black = RGBColor(r: 0, g: 0, b: 0)
        let white = RGBColor(r: 255, g: 255, b: 255)
        let red = RGBColor(r: 255, g: 0, b: 0)
        XCTAssertEqual(black.luminance, 0.0, accuracy: 1e-9)
        XCTAssertEqual(white.luminance, 1.0, accuracy: 1e-9)
        XCTAssertLessThan(red.luminance, white.luminance)
        XCTAssertGreaterThan(red.luminance, black.luminance)
    }

    func testHexFormatting() {
        XCTAssertEqual(RGBColor(r: 0, g: 0, b: 0).hex, "#000000")
        XCTAssertEqual(RGBColor(r: 255, g: 255, b: 255).hex, "#FFFFFF")
        XCTAssertEqual(RGBColor(r: 0xAB, g: 0xCD, b: 0xEF).hex, "#ABCDEF")
    }
}
