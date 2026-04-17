import Foundation

/// A labelled region in a generated puzzle.
public struct PuzzleRegion: Equatable, Codable, Sendable {
    /// Zero-based unique region id.
    public let id: Int
    /// Index into `ColorPalette.colors` — the color this region should be filled with.
    public let colorIndex: Int
    /// Number of pixels in this region (at the working resolution).
    public let pixelCount: Int
    /// Axis-aligned bounding box (inclusive) in working-image coordinates.
    public let bounds: PixelRect
    /// Centroid (in working-image coordinates) — convenient anchor for the number label.
    public let centroid: PixelPoint

    public init(
        id: Int,
        colorIndex: Int,
        pixelCount: Int,
        bounds: PixelRect,
        centroid: PixelPoint
    ) {
        self.id = id
        self.colorIndex = colorIndex
        self.pixelCount = pixelCount
        self.bounds = bounds
        self.centroid = centroid
    }
}

public struct PixelPoint: Equatable, Codable, Sendable {
    public let x: Int
    public let y: Int
    public init(x: Int, y: Int) { self.x = x; self.y = y }
}

public struct PixelRect: Equatable, Codable, Sendable {
    public let minX: Int
    public let minY: Int
    public let maxX: Int
    public let maxY: Int
    public init(minX: Int, minY: Int, maxX: Int, maxY: Int) {
        self.minX = minX; self.minY = minY; self.maxX = maxX; self.maxY = maxY
    }
    public var width: Int { maxX - minX + 1 }
    public var height: Int { maxY - minY + 1 }
}

/// Connected-components labeler with 4-connectivity. Operates on an array of
/// palette-index labels (the output of `KMeansQuantizer.quantize`). Returns a
/// region-id map (one id per pixel, same layout as the input label array) plus
/// the list of regions.
public enum ConnectedComponents {

    public struct Result: Equatable {
        public let regionIds: [Int]
        public let regions: [PuzzleRegion]
    }

    public static func label(
        colorIndices: [Int],
        width: Int,
        height: Int
    ) -> Result {
        precondition(colorIndices.count == width * height, "colorIndices size mismatch")
        guard width > 0 && height > 0 else {
            return Result(regionIds: [], regions: [])
        }

        var regionIds = [Int](repeating: -1, count: colorIndices.count)
        var regions: [PuzzleRegion] = []
        var stack: [(Int, Int)] = []
        stack.reserveCapacity(256)

        for y in 0..<height {
            for x in 0..<width {
                let startOffset = y * width + x
                if regionIds[startOffset] != -1 { continue }
                let targetColor = colorIndices[startOffset]
                let newId = regions.count

                // Flood fill with an explicit stack to avoid recursion depth limits.
                stack.removeAll(keepingCapacity: true)
                stack.append((x, y))
                regionIds[startOffset] = newId

                var pixelCount = 0
                var sumX = 0
                var sumY = 0
                var minX = x, maxX = x, minY = y, maxY = y

                while let (cx, cy) = stack.popLast() {
                    pixelCount += 1
                    sumX += cx
                    sumY += cy
                    if cx < minX { minX = cx }
                    if cx > maxX { maxX = cx }
                    if cy < minY { minY = cy }
                    if cy > maxY { maxY = cy }

                    // 4-connected neighbours.
                    let neighbours = [(cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)]
                    for (nx, ny) in neighbours {
                        if nx < 0 || nx >= width || ny < 0 || ny >= height { continue }
                        let noff = ny * width + nx
                        if regionIds[noff] != -1 { continue }
                        if colorIndices[noff] != targetColor { continue }
                        regionIds[noff] = newId
                        stack.append((nx, ny))
                    }
                }

                let centroid = PixelPoint(x: sumX / pixelCount, y: sumY / pixelCount)
                let bounds = PixelRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
                regions.append(
                    PuzzleRegion(
                        id: newId,
                        colorIndex: targetColor,
                        pixelCount: pixelCount,
                        bounds: bounds,
                        centroid: centroid
                    )
                )
            }
        }

        return Result(regionIds: regionIds, regions: regions)
    }

    /// Merge regions smaller than `minPixelCount` into a neighbouring region.
    /// This prevents kids from having to fill unpaintably tiny regions.
    /// The neighbour chosen is the one with the longest shared boundary; if
    /// there are no neighbours (e.g. a 1-pixel image) the region is kept.
    public static func mergeSmallRegions(
        _ input: Result,
        width: Int,
        height: Int,
        minPixelCount: Int
    ) -> Result {
        guard minPixelCount > 1 else { return input }
        guard !input.regions.isEmpty else { return input }

        // Union-find over region ids.
        var parent = Array(0..<input.regions.count)
        func find(_ i: Int) -> Int {
            var cur = i
            while parent[cur] != cur {
                parent[cur] = parent[parent[cur]]
                cur = parent[cur]
            }
            return cur
        }

        // Build neighbour maps keyed by region id.
        var neighbourCounts = [[Int: Int]](repeating: [:], count: input.regions.count)
        for y in 0..<height {
            for x in 0..<width {
                let r = input.regionIds[y * width + x]
                if x + 1 < width {
                    let r2 = input.regionIds[y * width + (x + 1)]
                    if r != r2 {
                        neighbourCounts[r][r2, default: 0] += 1
                        neighbourCounts[r2][r, default: 0] += 1
                    }
                }
                if y + 1 < height {
                    let r2 = input.regionIds[(y + 1) * width + x]
                    if r != r2 {
                        neighbourCounts[r][r2, default: 0] += 1
                        neighbourCounts[r2][r, default: 0] += 1
                    }
                }
            }
        }

        // Small regions pick their largest-boundary neighbour and merge into it.
        let smallRegions = input.regions
            .filter { $0.pixelCount < minPixelCount }
            .sorted { $0.pixelCount < $1.pixelCount }

        for region in smallRegions {
            guard let (bestNeighbour, _) = neighbourCounts[region.id].max(by: { $0.value < $1.value }) else {
                continue
            }
            let a = find(region.id)
            let b = find(bestNeighbour)
            if a != b { parent[a] = b }
        }

        // Remap region ids and rebuild the region list.
        var rootToNewId: [Int: Int] = [:]
        var newRegionIds = [Int](repeating: -1, count: input.regionIds.count)
        for i in 0..<input.regionIds.count {
            let root = find(input.regionIds[i])
            if let id = rootToNewId[root] {
                newRegionIds[i] = id
            } else {
                let id = rootToNewId.count
                rootToNewId[root] = id
                newRegionIds[i] = id
            }
        }

        // Recompute region metadata. Each merged root inherits the color of
        // the largest original region in its group (makes the result match the
        // visually dominant neighbour).
        var largestByRoot: [Int: PuzzleRegion] = [:]
        for region in input.regions {
            let root = find(region.id)
            if let existing = largestByRoot[root] {
                if region.pixelCount > existing.pixelCount {
                    largestByRoot[root] = region
                }
            } else {
                largestByRoot[root] = region
            }
        }

        var sumX = [Int](repeating: 0, count: rootToNewId.count)
        var sumY = [Int](repeating: 0, count: rootToNewId.count)
        var counts = [Int](repeating: 0, count: rootToNewId.count)
        var minX = [Int](repeating: Int.max, count: rootToNewId.count)
        var maxX = [Int](repeating: Int.min, count: rootToNewId.count)
        var minY = [Int](repeating: Int.max, count: rootToNewId.count)
        var maxY = [Int](repeating: Int.min, count: rootToNewId.count)

        for y in 0..<height {
            for x in 0..<width {
                let newId = newRegionIds[y * width + x]
                counts[newId] += 1
                sumX[newId] += x
                sumY[newId] += y
                if x < minX[newId] { minX[newId] = x }
                if x > maxX[newId] { maxX[newId] = x }
                if y < minY[newId] { minY[newId] = y }
                if y > maxY[newId] { maxY[newId] = y }
            }
        }

        var newRegions: [PuzzleRegion] = []
        newRegions.reserveCapacity(rootToNewId.count)
        for (root, newId) in rootToNewId.sorted(by: { $0.value < $1.value }) {
            let color = largestByRoot[root]!.colorIndex
            newRegions.append(
                PuzzleRegion(
                    id: newId,
                    colorIndex: color,
                    pixelCount: counts[newId],
                    bounds: PixelRect(
                        minX: minX[newId],
                        minY: minY[newId],
                        maxX: maxX[newId],
                        maxY: maxY[newId]
                    ),
                    centroid: PixelPoint(
                        x: sumX[newId] / counts[newId],
                        y: sumY[newId] / counts[newId]
                    )
                )
            )
        }

        return Result(regionIds: newRegionIds, regions: newRegions)
    }
}
