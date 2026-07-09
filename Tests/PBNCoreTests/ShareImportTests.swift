import XCTest
@testable import PBNCore

final class ShareImportTests: XCTestCase {
    // Extension and host must agree on URL construction or valid shares will be stranded.
    func testRoundTripOpenURL() {
        let token = "abc-123"
        let url = ShareImport.openURL(for: token)
        XCTAssertEqual(url.scheme, "paintbynumbers")
        XCTAssertEqual(url.host, "import")
        XCTAssertEqual(ShareImport.token(from: url), token)
    }

    // Other URL schemes must not be accepted as trusted share handoffs.
    func testRejectsWrongScheme() {
        let url = URL(string: "https://example.com/import?token=xxx")!
        XCTAssertNil(ShareImport.token(from: url))
    }

    // Only the import endpoint may consume inbox payloads.
    func testRejectsWrongHost() {
        let url = URL(string: "paintbynumbers://export?token=xxx")!
        XCTAssertNil(ShareImport.token(from: url))
    }

    // A handoff without a token cannot be bound to a specific payload safely.
    func testRejectsMissingToken() {
        let url = URL(string: "paintbynumbers://import")!
        XCTAssertNil(ShareImport.token(from: url))
    }

    // Empty tokens must not resolve broad or ambiguous inbox paths.
    func testRejectsEmptyToken() {
        let url = URL(string: "paintbynumbers://import?token=")!
        XCTAssertNil(ShareImport.token(from: url))
    }

    // Payload encoding compatibility is required across the extension process boundary.
    func testPayloadCodableRoundTrip() throws {
        // Use default JSON strategies to match production `JSONEncoder()` /
        // `JSONDecoder()` used in `ShareViewController` and `PuzzleLibrary`.
        let payload = ShareImportPayload(
            token: "tkn-123",
            filename: "incoming.jpg",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(ShareImportPayload.self, from: data)
        XCTAssertEqual(decoded, payload)
    }

    // MARK: Token validation

    // UUID-compatible tokens must remain accepted so normal extension handoffs work.
    func testIsValidTokenAcceptsUUID() {
        XCTAssertTrue(ShareImport.isValidToken(UUID().uuidString))
        XCTAssertTrue(ShareImport.isValidToken("abc-123"))
        XCTAssertTrue(ShareImport.isValidToken("A1B2C3"))
    }

    // Token allowlisting is the first defense against path traversal from custom URLs.
    func testIsValidTokenRejectsPathTraversal() {
        XCTAssertFalse(ShareImport.isValidToken(""))
        XCTAssertFalse(ShareImport.isValidToken("../etc/passwd"))
        XCTAssertFalse(ShareImport.isValidToken("foo/bar"))
        XCTAssertFalse(ShareImport.isValidToken("foo\\bar"))
        XCTAssertFalse(ShareImport.isValidToken("foo bar"))
        XCTAssertFalse(ShareImport.isValidToken("foo.bar"))
        XCTAssertFalse(ShareImport.isValidToken(String(repeating: "a", count: 65)))
    }

    // Percent-encoding must not bypass token path-traversal validation.
    func testTokenFromURLRejectsPathTraversalToken() {
        let url = URL(string: "paintbynumbers://import?token=..%2Fevil")!
        XCTAssertNil(ShareImport.token(from: url))
    }

    // Shared filenames become filesystem path components, so separators and
    // dot components must be rejected even when an attacker controls metadata.
    func testSafeFilenameRequiresSingleComponent() {
        XCTAssertTrue(ShareImport.isSafeFilename("ABC-123.png"))
        XCTAssertFalse(ShareImport.isSafeFilename("../image.png"))
        XCTAssertFalse(ShareImport.isSafeFilename("folder/image.png"))
        XCTAssertFalse(ShareImport.isSafeFilename("folder\\image.png"))
    }
}

final class SeededGeneratorTests: XCTestCase {
    // Equal seeds must yield equal random streams for reproducible quantization.
    func testSameSeedProducesSameSequence() {
        var a = SeededGenerator(seed: 1234)
        var b = SeededGenerator(seed: 1234)
        for _ in 0..<16 {
            XCTAssertEqual(a.next(), b.next())
        }
    }

    // Different seeds must actually vary output or the seed control is ineffective.
    func testDifferentSeedsDiverge() {
        var a = SeededGenerator(seed: 1)
        var b = SeededGenerator(seed: 2)
        var differed = false
        for _ in 0..<8 where a.next() != b.next() {
            differed = true
        }
        XCTAssertTrue(differed)
    }

    // A zero seed must not trap the generator in an all-zero state.
    func testZeroSeedStillProducesNonZero() {
        var a = SeededGenerator(seed: 0)
        let first = a.next()
        XCTAssertNotEqual(first, 0)
    }
}
