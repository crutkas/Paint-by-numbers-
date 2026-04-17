import UIKit
import CoreGraphics
import CoreImage
import PBNCore

extension UIImage {
    /// Convert to a platform-agnostic `RGBImage` by drawing into a 32-bit ARGB
    /// bitmap context. The longest edge is capped at `maxDimension` to keep
    /// generation fast on older devices.
    func rgbImage(maxDimension: Int = 512) -> RGBImage? {
        // Prefer the backing CGImage. If the UIImage is CI-backed (rare for
        // user-picked photos), materialize it via a CIContext first.
        let resolvedCGImage: CGImage? = {
            if let cg = self.cgImage { return cg }
            if let ci = self.ciImage {
                return CIContext().createCGImage(ci, from: ci.extent)
            }
            return nil
        }()
        guard let cgImage = resolvedCGImage else { return nil }

        let srcW = cgImage.width
        let srcH = cgImage.height
        guard srcW > 0 && srcH > 0 else { return nil }

        let scale: Double
        if srcW >= srcH {
            scale = Double(min(srcW, maxDimension)) / Double(srcW)
        } else {
            scale = Double(min(srcH, maxDimension)) / Double(srcH)
        }
        let dstW = max(1, Int(Double(srcW) * scale))
        let dstH = max(1, Int(Double(srcH) * scale))

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let bytesPerRow = dstW * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * dstH)

        guard let ctx = buffer.withUnsafeMutableBytes({ bytes -> CGContext? in
            CGContext(
                data: bytes.baseAddress,
                width: dstW,
                height: dstH,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )
        }) else { return nil }

        ctx.interpolationQuality = .medium
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: dstW, height: dstH))

        var pixels = [RGBColor]()
        pixels.reserveCapacity(dstW * dstH)
        for y in 0..<dstH {
            for x in 0..<dstW {
                let i = y * bytesPerRow + x * 4
                pixels.append(RGBColor(r: buffer[i], g: buffer[i + 1], b: buffer[i + 2]))
            }
        }
        return RGBImage(width: dstW, height: dstH, pixels: pixels)
    }
}
