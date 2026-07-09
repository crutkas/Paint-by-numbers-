import XCTest
@testable import PBNCore

final class RegionMapTests: XCTestCase {
    // Protects lossless hit-testing for puzzles with more regions than an
    // 8-bit image can represent; IDs above 255 must survive persistence.
    func testRoundTripPreservesLargeRegionIds() throws {
        let ids = [0, 255, 256, 65_535, 1_000_000, Int(UInt32.max)]
        let data = try RegionMap.encode(regionIds: ids, width: 3, height: 2)
        XCTAssertEqual(try RegionMap.decode(data, expectedWidth: 3, expectedHeight: 2), ids)
    }

    // Corrupt or mismatched maps must fail closed so a tap can never paint a
    // different region merely because persisted dimensions are stale.
    func testDecodeRejectsWrongDimensionsAndTruncatedData() throws {
        let data = try RegionMap.encode(regionIds: [0, 1, 2, 3], width: 2, height: 2)
        XCTAssertThrowsError(try RegionMap.decode(data, expectedWidth: 4, expectedHeight: 1))
        XCTAssertThrowsError(try RegionMap.decode(Data(data.dropLast()), expectedWidth: 2, expectedHeight: 2))
    }

    // Region bounds may overlap for freeform shapes, so exact coordinate
    // lookup—not nearest-centroid approximation—must decide the painted ID.
    func testCoordinateLookupUsesExactMapForOverlappingBounds() {
        let ids = [
            0, 1,
            1, 0
        ]
        XCTAssertEqual(RegionMap.regionId(atX: 1, y: 0, regionIds: ids, width: 2, height: 2), 1)
        XCTAssertEqual(RegionMap.regionId(atX: 1, y: 1, regionIds: ids, width: 2, height: 2), 0)
        XCTAssertNil(RegionMap.regionId(atX: 2, y: 0, regionIds: ids, width: 2, height: 2))
    }
}
