import XCTest
@testable import PBNCore

final class PuzzleStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PBNCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir, FileManager.default.fileExists(atPath: tempDir.path) {
            try FileManager.default.removeItem(at: tempDir)
        }
    }

    private func makeMetadata() -> PuzzleMetadata {
        let palette = ColorPalette(colors: [RGBColor(r: 255, g: 0, b: 0)])
        let regions = [
            PuzzleRegion(id: 0, colorIndex: 0, pixelCount: 4,
                         bounds: PixelRect(minX: 0, minY: 0, maxX: 1, maxY: 1),
                         centroid: PixelPoint(x: 0, y: 0))
        ]
        return PuzzleMetadata(
            title: "My Kitten",
            difficulty: .medium,
            strategy: .freeformRegions,
            workingWidth: 2,
            workingHeight: 2,
            palette: palette,
            regions: regions,
            sourceImageFilename: "source.png",
            regionMapFilename: "regionMap.png"
        )
    }

    func testSaveAndLoadMetadataRoundTrip() throws {
        let store = PuzzleStore(rootDirectory: tempDir)
        let original = makeMetadata()
        try store.saveMetadata(original)
        let loaded = try store.loadMetadata(id: original.id)
        // Dates go through JSON-encoded doubles, which can lose a few
        // nanoseconds of precision; everything else must round-trip exactly.
        XCTAssertEqual(loaded.id, original.id)
        XCTAssertEqual(loaded.title, original.title)
        XCTAssertEqual(loaded.difficulty, original.difficulty)
        XCTAssertEqual(loaded.strategy, original.strategy)
        XCTAssertEqual(loaded.workingWidth, original.workingWidth)
        XCTAssertEqual(loaded.workingHeight, original.workingHeight)
        XCTAssertEqual(loaded.palette, original.palette)
        XCTAssertEqual(loaded.regions, original.regions)
        XCTAssertEqual(loaded.sourceImageFilename, original.sourceImageFilename)
        XCTAssertEqual(loaded.regionMapFilename, original.regionMapFilename)
        XCTAssertEqual(loaded.outlineFilename, original.outlineFilename)
        XCTAssertEqual(
            loaded.createdAt.timeIntervalSince1970,
            original.createdAt.timeIntervalSince1970,
            accuracy: 0.001
        )
        XCTAssertEqual(
            loaded.lastEditedAt.timeIntervalSince1970,
            original.lastEditedAt.timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    func testLoadMetadataForMissingIdThrows() {
        let store = PuzzleStore(rootDirectory: tempDir)
        XCTAssertThrowsError(try store.loadMetadata(id: UUID()))
    }

    func testProgressRoundTripAndDefault() throws {
        let store = PuzzleStore(rootDirectory: tempDir)
        let meta = makeMetadata()
        try store.saveMetadata(meta)

        // With no stored progress, the store returns a fresh one.
        let fresh = try store.loadProgress(id: meta.id)
        XCTAssertEqual(fresh.puzzleId, meta.id)
        XCTAssertTrue(fresh.filledRegionIds.isEmpty)

        var progress = fresh
        progress.filledRegionIds = [0]
        progress.lastEditedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try store.saveProgress(progress)

        let loaded = try store.loadProgress(id: meta.id)
        XCTAssertEqual(loaded.filledRegionIds, [0])
        XCTAssertEqual(loaded.lastEditedAt.timeIntervalSince1970, 1_700_000_000, accuracy: 0.001)
    }

    func testListPuzzlesReturnsNewestFirst() throws {
        let store = PuzzleStore(rootDirectory: tempDir)

        var older = makeMetadata()
        older.lastEditedAt = Date(timeIntervalSince1970: 1_000_000_000)
        try store.saveMetadata(older)

        var newer = makeMetadata()
        newer.lastEditedAt = Date(timeIntervalSince1970: 2_000_000_000)
        try store.saveMetadata(newer)

        let all = try store.listPuzzles()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.first?.id, newer.id)
        XCTAssertEqual(all.last?.id, older.id)
    }

    func testDeleteRemovesPuzzleFolder() throws {
        let store = PuzzleStore(rootDirectory: tempDir)
        let meta = makeMetadata()
        try store.saveMetadata(meta)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.puzzleDirectory(id: meta.id).path))
        try store.delete(id: meta.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.puzzleDirectory(id: meta.id).path))
    }

    func testListPuzzlesReturnsEmptyWhenRootMissing() throws {
        let store = PuzzleStore(rootDirectory: tempDir)
        XCTAssertEqual(try store.listPuzzles().count, 0)
    }
}
