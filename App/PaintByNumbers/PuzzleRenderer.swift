import UIKit
import PBNCore

enum PuzzleRenderer {
    static func render(
        puzzle: PuzzleMetadata,
        progress: PuzzleProgress,
        regionIds: [Int]
    ) -> UIImage? {
        guard puzzle.workingWidth > 0, puzzle.workingHeight > 0,
              puzzle.sourcePixelWidth > 0, puzzle.sourcePixelHeight > 0,
              regionIds.count == puzzle.workingWidth * puzzle.workingHeight else { return nil }
    let pixelCount = puzzle.sourcePixelWidth.multipliedReportingOverflow(by: puzzle.sourcePixelHeight)
    let byteCount = pixelCount.partialValue.multipliedReportingOverflow(by: 4)
    guard !pixelCount.overflow, !byteCount.overflow else { return nil }
    let regions = Dictionary(uniqueKeysWithValues: puzzle.regions.map { ($0.id, $0) })
    var bytes = [UInt8](repeating: 255, count: byteCount.partialValue)
    for outputY in 0..<puzzle.sourcePixelHeight {
        let mapY = min(
            puzzle.workingHeight - 1,
            outputY * puzzle.workingHeight / puzzle.sourcePixelHeight
        )
        for outputX in 0..<puzzle.sourcePixelWidth {
            let mapX = min(
                puzzle.workingWidth - 1,
                outputX * puzzle.workingWidth / puzzle.sourcePixelWidth
            )
            let regionId = regionIds[mapY * puzzle.workingWidth + mapX]
            guard progress.filledRegionIds.contains(regionId),
                  let region = regions[regionId],
                  puzzle.palette.colors.indices.contains(region.colorIndex) else { continue }
            let color = puzzle.palette.colors[region.colorIndex]
            let offset = (outputY * puzzle.sourcePixelWidth + outputX) * 4
            bytes[offset] = color.r
            bytes[offset + 1] = color.g
            bytes[offset + 2] = color.b
            bytes[offset + 3] = 255
        }
    }
    let bytesPerRow = puzzle.sourcePixelWidth * 4
    let context = bytes.withUnsafeMutableBytes { buffer in
        CGContext(
            data: buffer.baseAddress,
            width: puzzle.sourcePixelWidth,
            height: puzzle.sourcePixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }
    guard let image = context?.makeImage() else { return nil }
    return UIImage(cgImage: image, scale: 1, orientation: .up)
}
