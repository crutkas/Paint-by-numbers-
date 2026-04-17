import Foundation

/// A palette produced by quantization: an ordered list of colors, each with
/// a user-facing number (1-based index).
public struct ColorPalette: Equatable, Codable, Sendable {
    public let colors: [RGBColor]

    public init(colors: [RGBColor]) {
        self.colors = colors
    }

    /// 1-based number shown to the user for a given color index.
    public func number(for index: Int) -> Int { index + 1 }
}

/// K-means color quantizer operating directly on `RGBImage`.
///
/// The implementation uses the k-means++ seeding strategy for good initial
/// clusters and iterates until assignments stabilize or the iteration cap
/// is hit. Distances are computed in RGB space — the plan calls for Lab on
/// device (via `CoreImage`/`CIKMeans`), but RGB keeps this layer portable
/// and testable on Linux.
public enum KMeansQuantizer {

    /// Quantize `image` to `k` colors.
    ///
    /// - Parameters:
    ///   - image: The source image.
    ///   - k: Target palette size. Clamped to `[1, image.pixels.count]`.
    ///   - maxIterations: Safety cap on the number of assignment/update rounds.
    ///   - seed: Seed for reproducible results. Defaults to a constant so the
    ///     same image always yields the same palette.
    /// - Returns: A tuple of the palette and a label array where `labels[i]`
    ///   is the palette index assigned to `image.pixels[i]`.
    public static func quantize(
        image: RGBImage,
        k: Int,
        maxIterations: Int = 20,
        seed: UInt64 = 0xC0FFEE
    ) -> (palette: ColorPalette, labels: [Int]) {
        let n = image.pixels.count
        guard n > 0 else {
            return (ColorPalette(colors: []), [])
        }
        let effectiveK = max(1, min(k, n))

        var rng = SeededGenerator(seed: seed)
        var centroids = seedCentroids(pixels: image.pixels, k: effectiveK, rng: &rng)
        var labels = [Int](repeating: 0, count: n)

        for _ in 0..<maxIterations {
            var changed = false

            // Assignment step.
            for i in 0..<n {
                let p = image.pixels[i]
                var bestIndex = 0
                var bestDist = p.squaredDistance(to: centroids[0])
                for c in 1..<centroids.count {
                    let d = p.squaredDistance(to: centroids[c])
                    if d < bestDist {
                        bestDist = d
                        bestIndex = c
                    }
                }
                if labels[i] != bestIndex {
                    labels[i] = bestIndex
                    changed = true
                }
            }

            // Update step.
            var sums = [(r: Int, g: Int, b: Int, count: Int)](
                repeating: (0, 0, 0, 0),
                count: centroids.count
            )
            for i in 0..<n {
                let p = image.pixels[i]
                let l = labels[i]
                sums[l].r += Int(p.r)
                sums[l].g += Int(p.g)
                sums[l].b += Int(p.b)
                sums[l].count += 1
            }
            for c in 0..<centroids.count where sums[c].count > 0 {
                centroids[c] = RGBColor(
                    ri: sums[c].r / sums[c].count,
                    gi: sums[c].g / sums[c].count,
                    bi: sums[c].b / sums[c].count
                )
            }

            if !changed { break }
        }

        // Drop any empty clusters to keep the palette tight.
        var used = Array(repeating: false, count: centroids.count)
        for l in labels { used[l] = true }
        if used.contains(false) {
            var remap = [Int](repeating: -1, count: centroids.count)
            var compact: [RGBColor] = []
            for c in 0..<centroids.count where used[c] {
                remap[c] = compact.count
                compact.append(centroids[c])
            }
            labels = labels.map { remap[$0] }
            centroids = compact
        }

        // Sort palette by luminance so "1" tends to be the darkest color;
        // this gives kids a consistent mental mapping.
        let order = centroids.indices.sorted { centroids[$0].luminance < centroids[$1].luminance }
        var indexMap = [Int](repeating: 0, count: centroids.count)
        for (newIdx, oldIdx) in order.enumerated() { indexMap[oldIdx] = newIdx }
        let sortedCentroids = order.map { centroids[$0] }
        let sortedLabels = labels.map { indexMap[$0] }

        return (ColorPalette(colors: sortedCentroids), sortedLabels)
    }

    /// k-means++ seeding: pick the first centroid uniformly at random, then
    /// each subsequent centroid with probability proportional to its squared
    /// distance from the nearest chosen centroid.
    private static func seedCentroids(
        pixels: [RGBColor],
        k: Int,
        rng: inout SeededGenerator
    ) -> [RGBColor] {
        var centroids: [RGBColor] = []
        centroids.reserveCapacity(k)

        let firstIndex = Int(rng.next() % UInt64(pixels.count))
        centroids.append(pixels[firstIndex])

        var distances = pixels.map { $0.squaredDistance(to: centroids[0]) }

        while centroids.count < k {
            let total = distances.reduce(0, +)
            if total == 0 {
                // All pixels are identical; just duplicate.
                centroids.append(centroids[0])
            } else {
                let target = Int(rng.next() % UInt64(total))
                var running = 0
                var pickedIndex = pixels.count - 1
                for i in 0..<pixels.count {
                    running += distances[i]
                    if running > target {
                        pickedIndex = i
                        break
                    }
                }
                centroids.append(pixels[pickedIndex])
            }

            // Update running minimum distances.
            let newCentroid = centroids.last!
            for i in 0..<pixels.count {
                let d = pixels[i].squaredDistance(to: newCentroid)
                if d < distances[i] { distances[i] = d }
            }
        }

        return centroids
    }
}
