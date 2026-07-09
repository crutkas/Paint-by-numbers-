import Foundation
import ImageIO
import UIKit

enum ImageImportValidator {
    // Limits are checked before decoding to bound both hostile inputs and
    // memory use on older supported devices. 25 MB covers normal HEIF/JPEG
    // photos, 12K permits high-resolution panoramas, and 40 MP caps decoded
    // RGBA memory near 160 MB before temporary rendering buffers.
    static let maximumFileBytes = 25 * 1_024 * 1_024 // Typical photos fit without admitting huge payloads.
    static let maximumDimension = 12_000 // Allows panoramas while bounding allocation width.
    static let maximumPixels = 40_000_000 // Approximately 160 MB of decoded RGBA pixels.

    enum ValidationError: LocalizedError {
        case tooLarge
        case invalidImage
        case dimensionsTooLarge

        var errorDescription: String? {
            switch self {
            case .tooLarge: return "That image file is larger than 25 MB."
            case .invalidImage: return "That file could not be read as an image."
            case .dimensionsTooLarge: return "That image has too many pixels to process safely."
            }
        }
    }

    static func image(from data: Data) throws -> UIImage {
        guard data.count <= maximumFileBytes else { throw ValidationError.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else { throw ValidationError.invalidImage }
        let pixels = width.multipliedReportingOverflow(by: height)
        guard !pixels.overflow,
              width <= maximumDimension,
              height <= maximumDimension,
              pixels.partialValue <= maximumPixels
        else { throw ValidationError.dimensionsTooLarge }
        guard let image = UIImage(data: data) else { throw ValidationError.invalidImage }
        return image
    }

    static func validate(_ image: UIImage) throws -> UIImage {
        guard let cgImage = image.cgImage else { throw ValidationError.invalidImage }
        let pixels = cgImage.width.multipliedReportingOverflow(by: cgImage.height)
        guard !pixels.overflow,
              cgImage.width <= maximumDimension,
              cgImage.height <= maximumDimension,
              pixels.partialValue <= maximumPixels
        else { throw ValidationError.dimensionsTooLarge }
        return image
    }
}
