import XCTest
@testable import PBNCore

final class RGBColorTests: XCTestCase {
    // Imported component values must clamp safely into the representable color range.
    func testClampingInit() {
        let c = RGBColor(ri: -5, gi: 300, bi: 128)
        XCTAssertEqual(c.r, 0)
        XCTAssertEqual(c.g, 255)
        XCTAssertEqual(c.b, 128)
    }

    // Symmetric distance is required for deterministic nearest-palette assignment.
    func testSquaredDistanceIsSymmetric() {
        let a = RGBColor(r: 10, g: 20, b: 30)
        let b = RGBColor(r: 40, g: 60, b: 80)
        XCTAssertEqual(a.squaredDistance(to: b), b.squaredDistance(to: a))
    }

    // A known distance protects the quantizer from arithmetic regressions.
    func testSquaredDistanceValue() {
        let a = RGBColor(r: 0, g: 0, b: 0)
        let b = RGBColor(r: 3, g: 4, b: 0)
        // 3^2 + 4^2 + 0 = 25
        XCTAssertEqual(a.squaredDistance(to: b), 25)
    }

    // Luminance must remain bounded and ordered so labels select readable contrast.
    func testLuminanceBoundsAndOrdering() {
        let black = RGBColor(r: 0, g: 0, b: 0)
        let white = RGBColor(r: 255, g: 255, b: 255)
        let red = RGBColor(r: 255, g: 0, b: 0)
        XCTAssertEqual(black.luminance, 0.0, accuracy: 1e-9)
        XCTAssertEqual(white.luminance, 1.0, accuracy: 1e-9)
        XCTAssertLessThan(red.luminance, white.luminance)
        XCTAssertGreaterThan(red.luminance, black.luminance)
    }

    // Stable hex output is required anywhere colors are serialized or diagnosed.
    func testHexFormatting() {
        XCTAssertEqual(RGBColor(r: 0, g: 0, b: 0).hex, "#000000")
        XCTAssertEqual(RGBColor(r: 255, g: 255, b: 255).hex, "#FFFFFF")
        XCTAssertEqual(RGBColor(r: 0xAB, g: 0xCD, b: 0xEF).hex, "#ABCDEF")
    }
}
