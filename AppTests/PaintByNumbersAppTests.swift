import XCTest
import PBNCore
@testable import PaintByNumbers

final class PaintByNumbersAppTests: XCTestCase {
    // Import limits are a security and reliability boundary: an encoded file
    // larger than the contract must be rejected before image decoding.
    func testImportRejectsOversizedEncodedData() {
        let data = Data(repeating: 0, count: ImageImportValidator.maximumFileBytes + 1)
        XCTAssertThrowsError(try ImageImportValidator.image(from: data))
    }

    // Malformed provider data is common across Files and Share extensions; it
    // must produce a recoverable error rather than a nil image or crash.
    func testImportRejectsMalformedImageData() {
        XCTAssertThrowsError(try ImageImportValidator.image(from: Data("not an image".utf8)))
    }

    // Freeform regions can share bounding boxes; export must color only pixels
    // owned by the exact map and preserve the original source dimensions.
    func testRendererUsesExactFreeformMapAtSourceResolution() throws {
        let regions = [
            PuzzleRegion(id: 0, colorIndex: 0, pixelCount: 2,
                         bounds: PixelRect(minX: 0, minY: 0, maxX: 1, maxY: 1),
                         centroid: PixelPoint(x: 0, y: 0)),
            PuzzleRegion(id: 1, colorIndex: 1, pixelCount: 2,
                         bounds: PixelRect(minX: 0, minY: 0, maxX: 1, maxY: 1),
                         centroid: PixelPoint(x: 1, y: 0))
        ]
        let puzzle = PuzzleMetadata(
            title: "Exact", difficulty: .easy, strategy: .freeformRegions,
            workingWidth: 2, workingHeight: 2, sourcePixelWidth: 20, sourcePixelHeight: 10,
            palette: ColorPalette(colors: [.init(r: 255, g: 0, b: 0), .init(r: 0, g: 0, b: 255)]),
            regions: regions, sourceImageFilename: "source.png", regionMapFilename: "map.pbnr"
        )
        let image = try XCTUnwrap(PuzzleRenderer.render(
            puzzle: puzzle,
            progress: PuzzleProgress(puzzleId: puzzle.id, filledRegionIds: [0]),
            regionIds: [0, 1, 1, 0]
        ))

        XCTAssertEqual(image.cgImage?.width, 20)
        XCTAssertEqual(image.cgImage?.height, 10)
        XCTAssertEqual(rgbaPixel(in: image, x: 2, y: 2), [255, 0, 0, 255])
        XCTAssertEqual(rgbaPixel(in: image, x: 15, y: 2), [255, 255, 255, 255])
        XCTAssertEqual(rgbaPixel(in: image, x: 2, y: 8), [255, 255, 255, 255])
        XCTAssertEqual(rgbaPixel(in: image, x: 15, y: 8), [255, 0, 0, 255])
    }

    // Square-grid export uses the same exact renderer as freeform output; this
    // guards the common path from regressing while freeform behavior evolves.
    func testRendererAcceptsSquareGridMap() {
        let region = PuzzleRegion(
            id: 0, colorIndex: 0, pixelCount: 1,
            bounds: PixelRect(minX: 0, minY: 0, maxX: 0, maxY: 0),
            centroid: PixelPoint(x: 0, y: 0)
        )
        let puzzle = PuzzleMetadata(
            title: "Grid", difficulty: .easy, strategy: .squareGrid(cellSize: 1),
            workingWidth: 1, workingHeight: 1,
            palette: ColorPalette(colors: [.init(r: 1, g: 2, b: 3)]),
            regions: [region], sourceImageFilename: "source.png", regionMapFilename: "map.pbnr"
        )
        XCTAssertNotNil(PuzzleRenderer.render(
            puzzle: puzzle,
            progress: PuzzleProgress(puzzleId: puzzle.id, filledRegionIds: [0]),
            regionIds: [0]
        ))
    }

    // Navigation must treat two imports of the same pixels as separate setup
    // sessions; identity-based wrappers prevent SwiftUI path deduplication.
    func testPendingImageNavigationUsesPerImportIdentity() {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in }
        let first = PendingImageWrapper(image: image)
        let second = PendingImageWrapper(image: image)

        XCTAssertNotEqual(first, second)
    }

    // This exercises the iOS lifecycle boundary from generated map through a
    // painted region and disk persistence, guarding state loss on navigation.
    func testGeneratedPaintingProgressPersists() throws {
        let source = RGBImage(width: 2, height: 1, pixels: [
            RGBColor(r: 255, g: 0, b: 0),
            RGBColor(r: 0, g: 0, b: 255)
        ])
        let generated = PuzzleGenerator.generate(
            image: source,
            difficulty: .easy,
            strategy: .squareGrid(cellSize: 1)
        )
        let metadata = PuzzleMetadata(
            title: "Lifecycle", difficulty: .easy, strategy: .squareGrid(cellSize: 1),
            workingWidth: generated.workingWidth, workingHeight: generated.workingHeight,
            palette: generated.palette, regions: generated.regions,
            sourceImageFilename: "source.png", regionMapFilename: "map.pbnr"
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaintByNumbersAppTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PuzzleStore(rootDirectory: directory)
        try store.saveMetadata(metadata)
        let progress = PuzzleProgress(puzzleId: metadata.id, filledRegionIds: [generated.regions[0].id])
        try store.saveProgress(progress)

        XCTAssertEqual(try store.loadProgress(id: metadata.id).filledRegionIds, progress.filledRegionIds)
    }

    // Settings are user-facing contracts rather than decorative toggles; each
    // key must round-trip through the same defaults store used by AppStorage.
    func testGameplaySettingsPersist() {
        let defaults = UserDefaults.standard
        let keys = [
            "pbn.sound", "pbn.haptics", "pbn.colorblindNumbers",
            "pbn.showColorBlocks", "pbn.removeDoneColors"
        ]
        defer { keys.forEach(defaults.removeObject(forKey:)) }
        for key in keys {
            defaults.set(false, forKey: key)
            XCTAssertFalse(defaults.bool(forKey: key), key)
            defaults.set(true, forKey: key)
            XCTAssertTrue(defaults.bool(forKey: key), key)
        }
    }

    // The extension and host must agree on identifiers and filename rules or
    // a valid handoff would silently strand the user's image in the inbox.
    func testShareExtensionHandoffContract() throws {
        let payload = ShareImportPayload(filename: "ABC-123.png")
        let url = ShareImport.openURL(for: payload.token)

        XCTAssertEqual(ShareImport.token(from: url), payload.token)
        XCTAssertTrue(ShareImport.isSafeFilename(payload.filename))
        XCTAssertEqual(AppConfiguration.appGroupIdentifier, "group.com.crutkas.paintbynumbers")
    }

    // VoiceOver users need actionable regions, not one opaque canvas element;
    // activating a region must use the same painting callback as touch input.
    func testCanvasExposesAccessibleRegionActions() throws {
        let region = PuzzleRegion(
            id: 7, colorIndex: 0, pixelCount: 1,
            bounds: PixelRect(minX: 0, minY: 0, maxX: 0, maxY: 0),
            centroid: PixelPoint(x: 0, y: 0)
        )
        let puzzle = PuzzleMetadata(
            title: "Accessible", difficulty: .easy, strategy: .squareGrid(cellSize: 1),
            workingWidth: 1, workingHeight: 1,
            palette: ColorPalette(colors: [.init(r: 1, g: 2, b: 3)]),
            regions: [region], sourceImageFilename: "source.png", regionMapFilename: "map.pbnr"
        )
        let view = PuzzleImageView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        var activatedRegion: Int?
        view.onTap = { activatedRegion = $0 }
        view.configure(puzzle: puzzle, regionIds: [7])

        XCTAssertFalse(view.isAccessibilityElement)
        let element = try XCTUnwrap(view.accessibilityElements?.first as? UIAccessibilityElement)
        XCTAssertEqual(element.accessibilityLabel, "Region for color 1")
        XCTAssertTrue(element.accessibilityActivate())
        XCTAssertEqual(activatedRegion, 7)
    }

    private func rgbaPixel(in image: UIImage, x: Int, y: Int) -> [UInt8]? {
        guard let cgImage = image.cgImage,
              x >= 0, x < cgImage.width, y >= 0, y < cgImage.height,
              let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return nil }
        let offset = y * cgImage.bytesPerRow + x * 4
        return Array(UnsafeBufferPointer(start: bytes + offset, count: 4))
    }
}
