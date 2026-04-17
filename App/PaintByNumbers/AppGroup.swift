import Foundation

/// Names and helpers for the App Group container shared between the main app
/// and the Share Extension.
public enum AppGroup {
    public static let identifier = "group.com.example.paintbynumbers"

    /// Shared container URL. Falls back to Application Support (or, if even
    /// that fails, the temporary directory) so debug builds without App Group
    /// entitlements still work instead of crashing at launch.
    public static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url
        }
        do {
            return try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        } catch {
            NSLog("AppGroup: Failed to resolve Application Support directory: \(error)")
            let fallback = FileManager.default.temporaryDirectory
                .appendingPathComponent("PaintByNumbers", isDirectory: true)
            try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
            return fallback
        }
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
