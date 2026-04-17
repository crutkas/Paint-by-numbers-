import Foundation

/// A simple row-major image of RGB pixels. Used as the cross-platform input to
/// all PBN algorithms so the pipeline is testable without `CoreGraphics`.
public struct RGBImage: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public var pixels: [RGBColor]

    public init(width: Int, height: Int, pixels: [RGBColor]) {
        precondition(width >= 0 && height >= 0, "width/height must be non-negative")
        precondition(pixels.count == width * height, "pixels.count must equal width*height")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public init(width: Int, height: Int, fill: RGBColor) {
        self.init(
            width: width,
            height: height,
            pixels: Array(repeating: fill, count: width * height)
        )
    }

    @inlinable
    public subscript(x: Int, y: Int) -> RGBColor {
        get {
            precondition(x >= 0 && x < width && y >= 0 && y < height, "index out of range")
            return pixels[y * width + x]
        }
        set {
            precondition(x >= 0 && x < width && y >= 0 && y < height, "index out of range")
            pixels[y * width + x] = newValue
        }
    }

    /// Returns a new image scaled to `targetWidth` x `targetHeight` using
    /// nearest-neighbor sampling. Suitable for downscaling the working image
    /// before quantization; the final rendered puzzle uses the original size.
    public func nearestNeighborScaled(toWidth targetWidth: Int, height targetHeight: Int) -> RGBImage {
        precondition(targetWidth > 0 && targetHeight > 0, "target dimensions must be positive")
        if targetWidth == width && targetHeight == height { return self }
        var out = [RGBColor]()
        out.reserveCapacity(targetWidth * targetHeight)
        for y in 0..<targetHeight {
            let sy = min(height - 1, (y * height) / targetHeight)
            for x in 0..<targetWidth {
                let sx = min(width - 1, (x * width) / targetWidth)
                out.append(pixels[sy * width + sx])
            }
        }
        return RGBImage(width: targetWidth, height: targetHeight, pixels: out)
    }
}
