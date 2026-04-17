import Foundation

/// Difficulty presets map to (grid density, palette size, min region size).
/// Designed for the 6-10 age range: `easy` produces big chunky cells with
/// few colors; `hard` preserves more of the source image.
public enum Difficulty: String, Codable, CaseIterable, Sendable {
    case easy
    case medium
    case hard

    /// Working-image long-edge resolution. Smaller == bigger, chunkier cells.
    public var workingLongEdge: Int {
        switch self {
        case .easy: return 64
        case .medium: return 128
        case .hard: return 192
        }
    }

    /// Target palette size.
    public var paletteSize: Int {
        switch self {
        case .easy: return 6
        case .medium: return 12
        case .hard: return 18
        }
    }

    /// Minimum pixel count (at working resolution) for a region to survive merge.
    public var minRegionPixels: Int {
        switch self {
        case .easy: return 24
        case .medium: return 12
        case .hard: return 6
        }
    }
}

/// Strategies for converting a quantized image into paintable regions.
///
/// - `.squareGrid`: overlays a square grid of `cellSize` pixels and replaces
///   each cell with the majority color, then runs connected-component labeling.
///   Easiest for young kids — every "region" is a cell.
/// - `.freeformRegions`: runs connected-component labeling on the raw
///   quantized image and merges small regions. More artistic for older kids.
public enum GridStrategy: Codable, Equatable, Sendable {
    case squareGrid(cellSize: Int)
    case freeformRegions
}

/// End-to-end puzzle generator. Takes an `RGBImage` and a `Difficulty` (plus
/// optional overrides) and produces a `GeneratedPuzzle`.
public enum PuzzleGenerator {

    /// Pure, deterministic output of the pipeline.
    public struct GeneratedPuzzle: Equatable, Sendable {
        public let palette: ColorPalette
        public let regions: [PuzzleRegion]
        /// Per-pixel region id, row-major, size `workingWidth * workingHeight`.
        public let regionIds: [Int]
        public let workingWidth: Int
        public let workingHeight: Int
        public let strategy: GridStrategy
        public let difficulty: Difficulty
    }

    public static func generate(
        image: RGBImage,
        difficulty: Difficulty = .medium,
        strategy: GridStrategy = .freeformRegions,
        seed: UInt64 = 0xC0FFEE
    ) -> GeneratedPuzzle {
        // 1. Downscale to the working resolution. An empty input short-circuits.
        let (ww, wh) = workingSize(forImage: image, difficulty: difficulty)
        guard ww > 0 && wh > 0 else {
            return GeneratedPuzzle(
                palette: ColorPalette(colors: []),
                regions: [],
                regionIds: [],
                workingWidth: 0,
                workingHeight: 0,
                strategy: strategy,
                difficulty: difficulty
            )
        }
        let working = image.nearestNeighborScaled(toWidth: ww, height: wh)

        // 2. Color-quantize.
        let (palette, labels) = KMeansQuantizer.quantize(
            image: working,
            k: difficulty.paletteSize,
            seed: seed
        )

        // 3. Apply grid strategy to obtain a "flattened" label array.
        let flattened: [Int]
        switch strategy {
        case .squareGrid(let cellSize):
            flattened = flattenToSquareGrid(
                labels: labels,
                width: ww,
                height: wh,
                cellSize: max(1, cellSize),
                paletteSize: palette.colors.count
            )
        case .freeformRegions:
            flattened = labels
        }

        // 4. Connected components + small-region merge.
        let raw = ConnectedComponents.label(colorIndices: flattened, width: ww, height: wh)
        let merged = ConnectedComponents.mergeSmallRegions(
            raw,
            width: ww,
            height: wh,
            minPixelCount: difficulty.minRegionPixels
        )

        return GeneratedPuzzle(
            palette: palette,
            regions: merged.regions,
            regionIds: merged.regionIds,
            workingWidth: ww,
            workingHeight: wh,
            strategy: strategy,
            difficulty: difficulty
        )
    }

    /// Pick a working size that preserves aspect ratio and whose long edge is
    /// `difficulty.workingLongEdge`. The short edge is rounded rather than
    /// floored so near-square images don't lose a pixel of aspect ratio.
    public static func workingSize(forImage image: RGBImage, difficulty: Difficulty) -> (Int, Int) {
        guard image.width > 0, image.height > 0 else { return (0, 0) }
        let target = difficulty.workingLongEdge
        if image.width >= image.height {
            let w = min(image.width, target)
            let h = max(1, Int(((Double(image.height) / Double(image.width)) * Double(w)).rounded()))
            return (w, h)
        } else {
            let h = min(image.height, target)
            let w = max(1, Int(((Double(image.width) / Double(image.height)) * Double(h)).rounded()))
            return (w, h)
        }
    }

    /// Replaces every `cellSize` x `cellSize` block with the majority color
    /// index found inside it. Produces flat, chunky cells ideal for young kids.
    private static func flattenToSquareGrid(
        labels: [Int],
        width: Int,
        height: Int,
        cellSize: Int,
        paletteSize: Int
    ) -> [Int] {
        var out = labels
        var histogram = [Int](repeating: 0, count: max(1, paletteSize))
        var y = 0
        while y < height {
            var x = 0
            while x < width {
                let x2 = min(width, x + cellSize)
                let y2 = min(height, y + cellSize)

                // Histogram within the cell.
                for i in 0..<histogram.count { histogram[i] = 0 }
                for yy in y..<y2 {
                    for xx in x..<x2 {
                        let c = labels[yy * width + xx]
                        if c >= 0 && c < histogram.count { histogram[c] += 1 }
                    }
                }

                // Majority.
                var bestIndex = 0
                var bestCount = histogram[0]
                for i in 1..<histogram.count where histogram[i] > bestCount {
                    bestCount = histogram[i]
                    bestIndex = i
                }

                for yy in y..<y2 {
                    for xx in x..<x2 {
                        out[yy * width + xx] = bestIndex
                    }
                }

                x += cellSize
            }
            y += cellSize
        }
        return out
    }
}
