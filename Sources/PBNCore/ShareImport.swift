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
    public static func token(from url: URL) -> String? {
        guard url.scheme == urlScheme else { return nil }
        guard url.host == "import" else { return nil }
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
            !token.isEmpty
        else { return nil }
        return token
    }
}
