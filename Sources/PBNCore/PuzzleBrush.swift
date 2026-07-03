import Foundation

/// Pure hit-testing helpers for the painting canvas. The app can ask for the
/// nearest region under a touch, or a larger "brush" footprint that returns
/// every nearby region in nearest-first order.
public enum PuzzleBrush {
    public static func regionIds(
        around point: PixelPoint,
        brushRadius: Int = 0,
        in puzzle: PuzzleMetadata
    ) -> [Int] {
        let radius = max(0, brushRadius)
        let radiusSquared = radius * radius

        struct Candidate {
            let regionId: Int
            let distanceToBoundsSquared: Int
            let distanceToCentroidSquared: Int
        }

        let candidates = puzzle.regions.compactMap { region -> Candidate? in
            // Clamp the touch point into the region's bounding box so we can
            // measure the true shortest distance from the touch to that box.
            let nearestX = min(max(point.x, region.bounds.minX), region.bounds.maxX)
            let nearestY = min(max(point.y, region.bounds.minY), region.bounds.maxY)
            let dx = nearestX - point.x
            let dy = nearestY - point.y
            let distanceToBoundsSquared = dx * dx + dy * dy
            guard distanceToBoundsSquared <= radiusSquared else { return nil }

            let centroidDX = region.centroid.x - point.x
            let centroidDY = region.centroid.y - point.y
            return Candidate(
                regionId: region.id,
                distanceToBoundsSquared: distanceToBoundsSquared,
                distanceToCentroidSquared: centroidDX * centroidDX + centroidDY * centroidDY
            )
        }
        .sorted {
            if $0.distanceToBoundsSquared != $1.distanceToBoundsSquared {
                return $0.distanceToBoundsSquared < $1.distanceToBoundsSquared
            }
            if $0.distanceToCentroidSquared != $1.distanceToCentroidSquared {
                return $0.distanceToCentroidSquared < $1.distanceToCentroidSquared
            }
            return $0.regionId < $1.regionId
        }

        guard radius > 0 else {
            return candidates.first.map { [$0.regionId] } ?? []
        }
        return candidates.map(\.regionId)
    }
}
