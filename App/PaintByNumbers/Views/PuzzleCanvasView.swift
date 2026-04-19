import SwiftUI
import UIKit
import PBNCore

/// UIKit-backed canvas for playing a puzzle. Renders the region id map plus
/// the filled-color overlay into a `UIImage`, shown inside a `UIScrollView`
/// for pinch-zoom and pan. Tapping a region fills it if the currently
/// selected palette number matches.
struct PuzzleCanvasView: UIViewRepresentable {
    let puzzle: PuzzleMetadata
    @Binding var progress: PuzzleProgress
    @Binding var selectedColorIndex: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(puzzle: puzzle)
    }

    func makeUIView(context: Context) -> PuzzleScrollView {
        let view = PuzzleScrollView()
        view.configure(with: puzzle, coordinator: context.coordinator)
        context.coordinator.onTapRegion = { regionId in
            handleTap(regionId: regionId, in: context.coordinator, view: view)
        }
        return view
    }

    func updateUIView(_ uiView: PuzzleScrollView, context: Context) {
        uiView.update(progress: progress, puzzle: puzzle)
    }

    private func handleTap(regionId: Int, in coordinator: Coordinator, view: PuzzleScrollView) {
        guard regionId >= 0 && regionId < puzzle.regions.count else { return }
        let region = puzzle.regions[regionId]
        guard region.colorIndex == selectedColorIndex else {
            // Intentionally no visual flash here — just a soft haptic nudge so
            // the wrong-color tap doesn't strobe the whole canvas red.
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }
        guard !progress.filledRegionIds.contains(regionId) else { return }
        progress.filledRegionIds.insert(regionId)
        progress.lastEditedAt = Date()
        view.redraw(progress: progress, puzzle: puzzle)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    final class Coordinator {
        let puzzle: PuzzleMetadata
        var onTapRegion: (Int) -> Void = { _ in }
        init(puzzle: PuzzleMetadata) { self.puzzle = puzzle }
    }
}

/// A zoomable container around a `PuzzleImageView`. Pulled out as a
/// `UIScrollView` so we can get efficient pinch-zoom/pan without SwiftUI
/// gesture recognizers fighting the canvas-tap gesture.
final class PuzzleScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = PuzzleImageView()
    /// Natural (un-zoomed) size of the canvas. Stored so we can recompute the
    /// fit-to-screen minimum zoom whenever the scroll view is resized.
    private var canvasSize: CGSize = .zero
    /// `true` until the first layout pass has applied the fit-to-screen zoom,
    /// so rotations / size changes after that don't keep snapping the user
    /// back to the fit scale.
    private var hasAppliedInitialZoom = false

    func configure(
        with puzzle: PuzzleMetadata,
        coordinator: PuzzleCanvasView.Coordinator
    ) {
        delegate = self
        // `minimumZoomScale` is recomputed in `layoutSubviews` once we know
        // our own bounds; we start permissive so the first pinch-out doesn't
        // snap back before layout runs.
        minimumZoomScale = 0.1
        maximumZoomScale = 8.0
        bouncesZoom = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        // Let kids swipe across the canvas with one finger to paint cells;
        // scrolling/panning the zoomed image requires two fingers.
        panGestureRecognizer.minimumNumberOfTouches = 2

        imageView.configure(puzzle: puzzle)
        imageView.onTap = { [weak coordinator] regionId in
            coordinator?.onTapRegion(regionId)
        }
        canvasSize = CGSize(
            width: puzzle.workingWidth * 8,
            height: puzzle.workingHeight * 8
        )
        imageView.frame = CGRect(origin: .zero, size: canvasSize)
        contentSize = canvasSize
        addSubview(imageView)
    }

    func update(progress: PuzzleProgress, puzzle: PuzzleMetadata) {
        imageView.update(progress: progress, puzzle: puzzle)
    }

    func redraw(progress: PuzzleProgress, puzzle: PuzzleMetadata) {
        imageView.update(progress: progress, puzzle: puzzle)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImageView()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        // Re-rasterize the canvas at the new zoom scale so numbers and region
        // outlines stay crisp instead of being scaled-up bitmap pixels.
        updateImageContentScale()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateMinimumZoomScaleForSize(bounds.size)
        if !hasAppliedInitialZoom, bounds.width > 0, bounds.height > 0, canvasSize != .zero {
            zoomScale = minimumZoomScale
            hasAppliedInitialZoom = true
            updateImageContentScale()
        }
        centerImageView()
    }

    /// Sets the canvas's `contentScaleFactor` to `screenScale * zoomScale` so
    /// `draw(_:)` produces a bitmap dense enough that numbers stay sharp at
    /// the current zoom level. Without this, UIKit just up-samples the
    /// existing (1x-rasterized) bitmap and the text looks blurry.
    private func updateImageContentScale() {
        let screenScale = (window?.screen.scale) ?? UIScreen.main.scale
        // Clamp to ≥1 so zooming out (fit-to-screen, which can be < 1 for
        // large puzzles) still rasterizes at the native screen density
        // rather than an even coarser one.
        let desired = screenScale * max(zoomScale, 1)
        // 0.01 is well below "one pixel" at any realistic device scale, so
        // it filters out the continuous micro-adjustments we'd otherwise
        // get from bounce/settle callbacks while still catching any real
        // zoom change.
        let capped = min(desired, screenScale * 4)
        if abs(imageView.contentScaleFactor - capped) > 0.01 {
            imageView.contentScaleFactor = capped
            imageView.setNeedsDisplay()
        }
    }

    /// Picks a `minimumZoomScale` that lets the whole canvas fit inside the
    /// visible bounds, so pinching out always reveals the full puzzle instead
    /// of bouncing back to 1:1.
    private func updateMinimumZoomScaleForSize(_ size: CGSize) {
        guard canvasSize.width > 0, canvasSize.height > 0,
              size.width > 0, size.height > 0 else { return }
        let xScale = size.width / canvasSize.width
        let yScale = size.height / canvasSize.height
        let fitScale = min(xScale, yScale)
        // Never go above 1.0 as the minimum — for small puzzles, fit > 1.0 and
        // we still want 1:1 as the "natural" lower bound.
        minimumZoomScale = min(1.0, fitScale)
        if maximumZoomScale < minimumZoomScale {
            maximumZoomScale = minimumZoomScale
        }
        if zoomScale < minimumZoomScale {
            zoomScale = minimumZoomScale
        }
    }

    /// Keeps the image view centered when it's smaller than the scroll view
    /// (i.e. when the user has zoomed out past 1:1). Without this the image
    /// sticks to the top-left corner and "snaps" visually during pinch.
    private func centerImageView() {
        let boundsSize = bounds.size
        var frame = imageView.frame
        frame.origin.x = frame.size.width < boundsSize.width
            ? (boundsSize.width - frame.size.width) / 2
            : 0
        frame.origin.y = frame.size.height < boundsSize.height
            ? (boundsSize.height - frame.size.height) / 2
            : 0
        imageView.frame = frame
    }
}

/// Owns the rasterized canvas and the region-id hit-test map.
final class PuzzleImageView: UIView {
    private var puzzle: PuzzleMetadata?
    private var regionIds: [Int] = []
    private var lastProgress: PuzzleProgress?
    private var lastSwipedRegionId: Int?
    /// Most recent pan sample location (in this view's coordinate space). We
    /// keep it so a fast swipe can be interpolated between callbacks — the
    /// pan recognizer only fires at display-refresh rate, so without
    /// interpolation a finger moving across ~5 cells per frame would have
    /// cells in the middle of each step silently skipped.
    private var lastSwipedPoint: CGPoint?
    var onTap: (Int) -> Void = { _ in }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        isUserInteractionEnabled = true
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)
        contentMode = .scaleAspectFit
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    func configure(puzzle: PuzzleMetadata) {
        self.puzzle = puzzle
        // The region-id map is persisted with the puzzle. In this scaffold we
        // re-generate it lazily from metadata when available.
        self.regionIds = []
        setNeedsDisplay()
    }

    func update(progress: PuzzleProgress, puzzle: PuzzleMetadata) {
        self.puzzle = puzzle
        self.lastProgress = progress
        setNeedsDisplay()
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        deliverRegion(atPoint: recognizer.location(in: self))
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let point = recognizer.location(in: self)
        switch recognizer.state {
        case .began:
            lastSwipedPoint = point
            deliverRegion(atPoint: point, dedupe: true)
        case .changed:
            // Walk from the previous pan sample to the current one in small
            // steps so a fast swipe covers every cell the finger actually
            // crossed, not just the ones sampled at display-refresh rate.
            deliverRegionsAlongSegment(from: lastSwipedPoint ?? point, to: point)
            lastSwipedPoint = point
        case .ended, .cancelled, .failed:
            lastSwipedRegionId = nil
            lastSwipedPoint = nil
        default:
            break
        }
    }

    /// Interpolates between two pan samples, delivering each distinct region
    /// along the way. Step size is sub-cell so neighboring cells on the path
    /// are never skipped even on a very fast swipe.
    private func deliverRegionsAlongSegment(from start: CGPoint, to end: CGPoint) {
        guard let puzzle, puzzle.workingWidth > 0, puzzle.workingHeight > 0,
              bounds.width > 0, bounds.height > 0 else {
            deliverRegion(atPoint: end, dedupe: true)
            return
        }
        // Pick a step size small enough that consecutive samples land in
        // adjacent working pixels at most. Using half the cell size in each
        // axis guarantees we don't tunnel past a 1-cell-wide region.
        let cellWidthInPoints = bounds.width / CGFloat(puzzle.workingWidth)
        let cellHeightInPoints = bounds.height / CGFloat(puzzle.workingHeight)
        let stepLength = max(0.5, min(cellWidthInPoints, cellHeightInPoints) * 0.5)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = (dx * dx + dy * dy).squareRoot()
        if distance <= stepLength {
            deliverRegion(atPoint: end, dedupe: true)
            return
        }
        let steps = max(1, Int((distance / stepLength).rounded(.up)))
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let p = CGPoint(x: start.x + dx * t, y: start.y + dy * t)
            deliverRegion(atPoint: p, dedupe: true)
        }
    }

    /// Finds the region under `point` and (unless already delivered this
    /// swipe) forwards it to `onTap`. `dedupe` keeps the pan gesture from
    /// firing continuously while the finger is inside a single region.
    private func deliverRegion(atPoint point: CGPoint, dedupe: Bool = false) {
        guard let puzzle, !puzzle.regions.isEmpty else { return }
        guard bounds.contains(point) else {
            if dedupe { lastSwipedRegionId = nil }
            return
        }
        let px = Int((point.x / bounds.width) * CGFloat(puzzle.workingWidth))
        let py = Int((point.y / bounds.height) * CGFloat(puzzle.workingHeight))
        // Without a stored region-id map we approximate: find the region whose
        // bounds contain the tap, preferring the one whose centroid is closest.
        var best: (Int, Double)? = nil
        for region in puzzle.regions {
            let b = region.bounds
            guard px >= b.minX && px <= b.maxX && py >= b.minY && py <= b.maxY else { continue }
            let dx = Double(region.centroid.x - px)
            let dy = Double(region.centroid.y - py)
            let dist = dx * dx + dy * dy
            if best == nil || dist < best!.1 { best = (region.id, dist) }
        }
        guard let best else { return }
        if dedupe {
            if lastSwipedRegionId == best.0 { return }
            lastSwipedRegionId = best.0
        }
        onTap(best.0)
    }

    override func draw(_ rect: CGRect) {
        guard let puzzle, let ctx = UIGraphicsGetCurrentContext() else { return }
        let w = CGFloat(puzzle.workingWidth)
        let h = CGFloat(puzzle.workingHeight)
        guard w > 0 && h > 0 else { return }
        let scaleX = bounds.width / w
        let scaleY = bounds.height / h

        // Pick a single font size for every numbered cell so the grid reads
        // like graph paper instead of a mix of giant and tiny digits. The
        // size is driven by the puzzle's nominal cell size (in working
        // pixels) — not by each region's individual rect, which varies at
        // the image edges — and clamped to a comfortable range.
        let baseCellPixels: CGFloat = {
            if case .squareGrid(let cs) = puzzle.strategy {
                return CGFloat(max(1, cs))
            }
            return 1
        }()
        let cellPoints = baseCellPixels * scaleX
        let fontSize = max(8, min(28, cellPoints * 0.35))
        let numberFont = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        let numberAttrs: [NSAttributedString.Key: Any] = [
            .font: numberFont,
            .foregroundColor: UIColor.label
        ]

        // Draw each region's bounding box: filled if completed, otherwise with
        // its number centered. A production build would replace this with the
        // vectorized outline paths generated during puzzle creation.
        for region in puzzle.regions {
            let b = region.bounds
            let rect = CGRect(
                x: CGFloat(b.minX) * scaleX,
                y: CGFloat(b.minY) * scaleY,
                width: CGFloat(b.width) * scaleX,
                height: CGFloat(b.height) * scaleY
            )
            if let progress = lastProgress, progress.filledRegionIds.contains(region.id) {
                let color = puzzle.palette.colors[region.colorIndex]
                ctx.setFillColor(
                    UIColor(
                        red: CGFloat(color.r) / 255,
                        green: CGFloat(color.g) / 255,
                        blue: CGFloat(color.b) / 255,
                        alpha: 1
                    ).cgColor
                )
                ctx.fill(rect)
            } else {
                ctx.setStrokeColor(UIColor.separator.cgColor)
                ctx.setLineWidth(0.5)
                ctx.stroke(rect)

                let number = "\(region.colorIndex + 1)"
                let size = (number as NSString).size(withAttributes: numberAttrs)
                // Skip the label if the cell is too small to fit it — keeps
                // a fine grid legible instead of a wall of overlapping text.
                guard size.width <= rect.width && size.height <= rect.height else { continue }
                let origin = CGPoint(
                    x: rect.midX - size.width / 2,
                    y: rect.midY - size.height / 2
                )
                (number as NSString).draw(at: origin, withAttributes: numberAttrs)
            }
        }
    }
}
