import Foundation

/// Handles the payload that the Share Extension writes into the shared App
/// Group container and that the host app consumes when opened via the custom
/// URL scheme (`paintbynumbers://import?token=...`).
///
/// Keeping this in `PBNCore` means it can be unit-tested without any iOS
/// framework dependencies.
public struct ShareImportPayload: Codable, Equatable, Sendable {
    /// Unique token embedded in the open-URL.
    public let token: String
    /// Filename (inside the App Group's `SharedInbox/` folder) of the raw image.
    public let filename: String
    /// When the payload was created.
    public let createdAt: Date

    public init(token: String = UUID().uuidString, filename: String, createdAt: Date = Date()) {
        self.token = token
        self.filename = filename
        self.createdAt = createdAt
    }
}

public enum ShareImport {

    /// The URL scheme the app registers.
    public static let urlScheme = "paintbynumbers"

    /// Build the open-URL a Share Extension should use to hand off to the app.
    public static func openURL(for token: String) -> URL {
        var components = URLComponents()
        components.scheme = urlScheme
        components.host = "import"
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        // `url` cannot be nil for these well-formed components.
        return components.url!
    }

    /// Parse an incoming URL and return the embedded token, if any.
    ///
    /// The token is validated to match a strict `[A-Za-z0-9-]{1,64}` shape
    /// (compatible with `UUID().uuidString`). Because *any* app on the
    /// device can invoke our custom URL scheme, a malicious caller could
    /// otherwise smuggle `../` path separators into the token that the host
    /// app later uses to build a filename inside the App Group container.
    /// Rejecting anything outside this allowlist prevents path traversal.
    public static func token(from url: URL) -> String? {
        guard url.scheme == urlScheme else { return nil }
        guard url.host == "import" else { return nil }
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let candidate = components.queryItems?.first(where: { $0.name == "token" })?.value,
            isValidToken(candidate)
        else { return nil }
        return candidate
    }

    /// Returns `true` iff `token` is a non-empty, short, filename-safe string.
    /// Exposed so app-layer code and the Share Extension can apply the same
    /// rule when minting or consuming tokens.
    public static func isValidToken(_ token: String) -> Bool {
        guard !token.isEmpty, token.count <= 64 else { return false }
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-"
        )
        return token.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
