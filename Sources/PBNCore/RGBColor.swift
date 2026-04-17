import Foundation

/// An RGB color using 8-bit unsigned channels. Platform-agnostic so it can be
/// used by both the core library (Linux/tests) and the iOS app.
public struct RGBColor: Hashable, Codable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// Initialize from 0-255 Int channels, clamped.
    public init(ri: Int, gi: Int, bi: Int) {
        self.r = UInt8(max(0, min(255, ri)))
        self.g = UInt8(max(0, min(255, gi)))
        self.b = UInt8(max(0, min(255, bi)))
    }

    /// Squared Euclidean distance in RGB space. Cheap and good enough for the
    /// initial k-means pass; the app can upgrade to Lab later.
    @inlinable
    public func squaredDistance(to other: RGBColor) -> Int {
        let dr = Int(r) - Int(other.r)
        let dg = Int(g) - Int(other.g)
        let db = Int(b) - Int(other.b)
        return dr * dr + dg * dg + db * db
    }

    /// Relative luminance (Rec. 709). Used to pick a legible number color
    /// (black on light regions, white on dark regions).
    public var luminance: Double {
        (0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)) / 255.0
    }

    /// Hex string like `#RRGGBB`.
    public var hex: String {
        String(format: "#%02X%02X%02X", r, g, b)
    }
}
