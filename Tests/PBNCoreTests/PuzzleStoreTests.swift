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

    // Metadata must survive disk persistence without losing puzzle identity or rendering inputs.
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

    // Missing puzzle IDs must be distinguishable from empty valid records for actionable errors.
    func testLoadMetadataForMissingIdThrows() {
        let store = PuzzleStore(rootDirectory: tempDir)
        XCTAssertThrowsError(try store.loadMetadata(id: UUID()))
    }

    // Progress defaults and saved painting state must both round-trip across app launches.
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

    // Library ordering must surface the puzzle edited most recently.
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

    // Deletion must remove every artifact so private images are not left behind.
    func testDeleteRemovesPuzzleFolder() throws {
        let store = PuzzleStore(rootDirectory: tempDir)
        let meta = makeMetadata()
        try store.saveMetadata(meta)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.puzzleDirectory(id: meta.id).path))
        try store.delete(id: meta.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.puzzleDirectory(id: meta.id).path))
    }

    // First launch has no storage root and must still present an empty usable library.
    func testListPuzzlesReturnsEmptyWhenRootMissing() throws {
        let store = PuzzleStore(rootDirectory: tempDir)
        XCTAssertEqual(try store.listPuzzles().count, 0)
    }

    // Existing installs have unversioned metadata without source dimensions;
    // migration must preserve those puzzles and supply safe export defaults.
    func testLegacyMetadataMigratesOnLoad() throws {
        let store = PuzzleStore(rootDirectory: tempDir)
        let metadata = makeMetadata()
        try store.saveMetadata(metadata)
        let url = store.puzzleDirectory(id: metadata.id).appendingPathComponent("metadata.json")
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        object.removeValue(forKey: "schemaVersion")
        object.removeValue(forKey: "sourcePixelWidth")
        object.removeValue(forKey: "sourcePixelHeight")
        try JSONSerialization.data(withJSONObject: object).write(to: url, options: .atomic)

        let migrated = try store.loadMetadata(id: metadata.id)
        XCTAssertEqual(migrated.schemaVersion, PuzzleMetadata.currentSchemaVersion)
        XCTAssertEqual(migrated.sourcePixelWidth, metadata.workingWidth)
        XCTAssertEqual(migrated.sourcePixelHeight, metadata.workingHeight)
    }

    // One malformed record must not make the entire library unusable; moving
    // it aside keeps recovery possible while healthy puzzles continue loading.
    func testListPuzzlesQuarantinesCorruptRecord() throws {
        let store = PuzzleStore(rootDirectory: tempDir)
        let metadata = makeMetadata()
        let directory = try store.createPuzzleDirectory(id: metadata.id)
        try Data("{not-json".utf8).write(
            to: directory.appendingPathComponent("metadata.json"),
            options: .atomic
        )

        XCTAssertTrue(try store.listPuzzles().isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathExtension("corrupt").path))
    }

    // Recovery must be visible to the UI while healthy puzzles remain usable;
    // returning a count prevents corruption from being silently hidden.
    func testListPuzzlesReportsQuarantinedRecords() throws {
        let store = PuzzleStore(rootDirectory: tempDir)
        let healthy = makeMetadata()
        try store.saveMetadata(healthy)
        let damagedId = UUID()
        let damaged = try store.createPuzzleDirectory(id: damagedId)
        try Data("broken".utf8).write(to: damaged.appendingPathComponent("metadata.json"))

        let result = try store.listPuzzlesWithRecovery()

        XCTAssertEqual(result.puzzles.map(\.id), [healthy.id])
        XCTAssertEqual(result.quarantinedPuzzleCount, 1)
    }

    // Duplicate region IDs make completion and exact-map lookup ambiguous, so
    // malformed metadata must be isolated rather than entering the library.
    func testListPuzzlesQuarantinesDuplicateRegionIds() throws {
        let store = PuzzleStore(rootDirectory: tempDir)
        let original = makeMetadata()
        let duplicate = PuzzleRegion(
            id: 0,
            colorIndex: 0,
            pixelCount: 1,
            bounds: PixelRect(minX: 1, minY: 1, maxX: 1, maxY: 1),
            centroid: PixelPoint(x: 1, y: 1)
        )
        let invalid = PuzzleMetadata(
            id: original.id,
            title: original.title,
            difficulty: original.difficulty,
            strategy: original.strategy,
            workingWidth: original.workingWidth,
            workingHeight: original.workingHeight,
            palette: original.palette,
            regions: original.regions + [duplicate],
            sourceImageFilename: original.sourceImageFilename,
            regionMapFilename: original.regionMapFilename
        )
        try store.saveMetadata(invalid)

        let result = try store.listPuzzlesWithRecovery()

        XCTAssertTrue(result.puzzles.isEmpty)
        XCTAssertEqual(result.quarantinedPuzzleCount, 1)
    }
}
