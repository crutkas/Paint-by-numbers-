import XCTest
@testable import PBNCore

final class ConnectedComponentsTests: XCTestCase {
    func testFourConnectedRegionsOnCheckerboard() {
        // 2x2 checkerboard: every cell is its own region.
        let labels = [0, 1, 1, 0]
        let r = ConnectedComponents.label(colorIndices: labels, width: 2, height: 2)
        XCTAssertEqual(r.regions.count, 4)
        XCTAssertEqual(Set(r.regionIds), [0, 1, 2, 3])
        for region in r.regions {
            XCTAssertEqual(region.pixelCount, 1)
        }
    }

    func testSingleColorImageIsOneRegion() {
        let labels = [Int](repeating: 7, count: 5 * 4)
        let r = ConnectedComponents.label(colorIndices: labels, width: 5, height: 4)
        XCTAssertEqual(r.regions.count, 1)
        XCTAssertEqual(r.regions[0].pixelCount, 20)
        XCTAssertEqual(r.regions[0].colorIndex, 7)
        XCTAssertEqual(r.regions[0].bounds.width, 5)
        XCTAssertEqual(r.regions[0].bounds.height, 4)
    }

    func testDiagonalPixelsDoNotMerge() {
        // 0 1
        // 1 0  — with 4-connectivity, each pixel is its own region.
        let labels = [0, 1, 1, 0]
        let r = ConnectedComponents.label(colorIndices: labels, width: 2, height: 2)
        XCTAssertEqual(r.regions.count, 4)
    }

    func testCentroidOfUniformRegion() {
        let labels = [Int](repeating: 0, count: 4 * 4)
        let r = ConnectedComponents.label(colorIndices: labels, width: 4, height: 4)
        XCTAssertEqual(r.regions.count, 1)
        // Centroid should be near the middle.
        XCTAssertEqual(r.regions[0].centroid.x, 1)
        XCTAssertEqual(r.regions[0].centroid.y, 1)
    }

    func testMergeSmallRegionsAbsorbsStrayPixel() {
        // 3x3: a sea of 0s with one stray 1 in the middle.
        // 0 0 0
        // 0 1 0
        // 0 0 0
        let labels = [0, 0, 0, 0, 1, 0, 0, 0, 0]
        let raw = ConnectedComponents.label(colorIndices: labels, width: 3, height: 3)
        XCTAssertEqual(raw.regions.count, 2)
        let merged = ConnectedComponents.mergeSmallRegions(
            raw,
            width: 3,
            height: 3,
            minPixelCount: 2
        )
        XCTAssertEqual(merged.regions.count, 1)
        XCTAssertEqual(merged.regions[0].pixelCount, 9)
        XCTAssertEqual(merged.regions[0].colorIndex, 0)
        XCTAssertTrue(merged.regionIds.allSatisfy { $0 == 0 })
    }

    func testMergeSmallRegionsLeavesLargeRegionsAlone() {
        // A 4x1 strip: left half color 0, right half color 1.
        let labels = [0, 0, 1, 1]
        let raw = ConnectedComponents.label(colorIndices: labels, width: 4, height: 1)
        XCTAssertEqual(raw.regions.count, 2)
        let merged = ConnectedComponents.mergeSmallRegions(
            raw, width: 4, height: 1, minPixelCount: 2
        )
        XCTAssertEqual(merged.regions.count, 2)
    }

    func testRegionIdsStayInsideRegionList() {
        let labels = [0, 1, 0, 1, 0, 1, 0, 1]
        let r = ConnectedComponents.label(colorIndices: labels, width: 2, height: 4)
        for id in r.regionIds {
            XCTAssertGreaterThanOrEqual(id, 0)
            XCTAssertLessThan(id, r.regions.count)
        }
    }
}
