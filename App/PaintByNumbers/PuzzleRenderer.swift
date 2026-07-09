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
        let size = CGSize(width: puzzle.sourcePixelWidth, height: puzzle.sourcePixelHeight)
        let regions = Dictionary(uniqueKeysWithValues: puzzle.regions.map { ($0.id, $0) })
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let scaleX = size.width / CGFloat(puzzle.workingWidth)
            let scaleY = size.height / CGFloat(puzzle.workingHeight)
            for y in 0..<puzzle.workingHeight {
                var x = 0
                while x < puzzle.workingWidth {
                    let regionId = regionIds[y * puzzle.workingWidth + x]
                    var end = x + 1
                    while end < puzzle.workingWidth,
                          regionIds[y * puzzle.workingWidth + end] == regionId {
                        end += 1
                    }
                    if progress.filledRegionIds.contains(regionId),
                       let region = regions[regionId],
                       puzzle.palette.colors.indices.contains(region.colorIndex) {
                        let color = puzzle.palette.colors[region.colorIndex]
                        UIColor(
                            red: CGFloat(color.r) / 255,
                            green: CGFloat(color.g) / 255,
                            blue: CGFloat(color.b) / 255,
                            alpha: 1
                        ).setFill()
                        context.fill(CGRect(
                            x: CGFloat(x) * scaleX,
                            y: CGFloat(y) * scaleY,
                            width: CGFloat(end - x) * scaleX,
                            height: scaleY
                        ))
                    }
                    x = end
                }
            }
        }
    }
}
