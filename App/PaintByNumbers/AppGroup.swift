import Foundation

/// Names and helpers for the App Group container shared between the main app
/// and the Share Extension.
public enum AppGroup {
    public static let identifier = "group.com.example.paintbynumbers"

    /// Shared container URL (nil if App Group entitlement is missing; in that
    /// case we fall back to the app's own Application Support).
    public static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url
        }
        // Fallback so debug builds without entitlements still work.
        let appSupport = try! FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport
    }

    /// Folder where the Share Extension drops incoming images.
    public static var sharedInboxURL: URL {
        let url = containerURL.appendingPathComponent("SharedInbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Root directory for puzzle storage.
    public static var puzzlesRootURL: URL {
        let url = containerURL.appendingPathComponent("PBN", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
