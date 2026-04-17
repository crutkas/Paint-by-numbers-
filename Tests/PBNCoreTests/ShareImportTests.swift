import XCTest
@testable import PBNCore

final class ShareImportTests: XCTestCase {
    func testRoundTripOpenURL() {
        let token = "abc-123"
        let url = ShareImport.openURL(for: token)
        XCTAssertEqual(url.scheme, "paintbynumbers")
        XCTAssertEqual(url.host, "import")
        XCTAssertEqual(ShareImport.token(from: url), token)
    }

    func testRejectsWrongScheme() {
        let url = URL(string: "https://example.com/import?token=xxx")!
        XCTAssertNil(ShareImport.token(from: url))
    }

    func testRejectsWrongHost() {
        let url = URL(string: "paintbynumbers://export?token=xxx")!
        XCTAssertNil(ShareImport.token(from: url))
    }

    func testRejectsMissingToken() {
        let url = URL(string: "paintbynumbers://import")!
        XCTAssertNil(ShareImport.token(from: url))
    }

    func testRejectsEmptyToken() {
        let url = URL(string: "paintbynumbers://import?token=")!
        XCTAssertNil(ShareImport.token(from: url))
    }

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

    func testIsValidTokenAcceptsUUID() {
        XCTAssertTrue(ShareImport.isValidToken(UUID().uuidString))
        XCTAssertTrue(ShareImport.isValidToken("abc-123"))
        XCTAssertTrue(ShareImport.isValidToken("A1B2C3"))
    }

    func testIsValidTokenRejectsPathTraversal() {
        XCTAssertFalse(ShareImport.isValidToken(""))
        XCTAssertFalse(ShareImport.isValidToken("../etc/passwd"))
        XCTAssertFalse(ShareImport.isValidToken("foo/bar"))
        XCTAssertFalse(ShareImport.isValidToken("foo\\bar"))
        XCTAssertFalse(ShareImport.isValidToken("foo bar"))
        XCTAssertFalse(ShareImport.isValidToken("foo.bar"))
        XCTAssertFalse(ShareImport.isValidToken(String(repeating: "a", count: 65)))
    }

    func testTokenFromURLRejectsPathTraversalToken() {
        let url = URL(string: "paintbynumbers://import?token=..%2Fevil")!
        XCTAssertNil(ShareImport.token(from: url))
    }
}

final class SeededGeneratorTests: XCTestCase {
    func testSameSeedProducesSameSequence() {
        var a = SeededGenerator(seed: 1234)
        var b = SeededGenerator(seed: 1234)
        for _ in 0..<16 {
            XCTAssertEqual(a.next(), b.next())
        }
    }

    func testDifferentSeedsDiverge() {
        var a = SeededGenerator(seed: 1)
        var b = SeededGenerator(seed: 2)
        var differed = false
        for _ in 0..<8 where a.next() != b.next() {
            differed = true
        }
        XCTAssertTrue(differed)
    }

    func testZeroSeedStillProducesNonZero() {
        var a = SeededGenerator(seed: 0)
        let first = a.next()
        XCTAssertNotEqual(first, 0)
    }
}
