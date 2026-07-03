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

    @AppStorage("pbn.showColorBlocks") private var showColorBlocks = false
    @AppStorage("pbn.haptics") private var hapticsOn = true
    @AppStorage("pbn.largeBrush") private var largeBrush = false

    func makeCoordinator() -> Coordinator {
        Coordinator(puzzle: puzzle)
    }

    func makeUIView(context: Context) -> PuzzleScrollView {
        let view = PuzzleScrollView()
        view.configure(with: puzzle, coordinator: context.coordinator)
        context.coordinator.onTapRegions = { regionIds in
            handleTap(regionIds: regionIds, in: context.coordinator, view: view)
        }
        return view
    }

    func updateUIView(_ uiView: PuzzleScrollView, context: Context) {
        uiView.update(
            progress: progress,
            puzzle: puzzle,
            highlightedColorIndex: showColorBlocks ? selectedColorIndex : nil,
            largeBrushEnabled: largeBrush
        )
    }

    private func handleTap(regionIds: [Int], in coordinator: Coordinator, view: PuzzleScrollView) {
        let validRegionIds = regionIds.filter { $0 >= 0 && $0 < puzzle.regions.count }
        guard !validRegionIds.isEmpty else { return }

        let fillableRegionIds = validRegionIds.filter { regionId in
            let region = puzzle.regions[regionId]
            return region.colorIndex == selectedColorIndex && !progress.filledRegionIds.contains(regionId)
        }

        guard !fillableRegionIds.isEmpty else {
            // Intentionally no visual flash here — just a soft haptic nudge so
            // the wrong-color tap doesn't strobe the whole canvas red.
            if hapticsOn {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            return
        }

        for regionId in fillableRegionIds {
            progress.filledRegionIds.insert(regionId)
        }
        progress.lastEditedAt = Date()
        view.redraw(
            progress: progress,
            puzzle: puzzle,
            highlightedColorIndex: showColorBlocks ? selectedColorIndex : nil,
            largeBrushEnabled: largeBrush
        )
        if hapticsOn {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    final class Coordinator {
        let puzzle: PuzzleMetadata
        var onTapRegions: ([Int]) -> Void = { _ in }
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
    /// Tracks whether the canvas is currently at the fit-to-screen zoom. We
    /// re-apply the fit zoom on resize only while this is true, so a user who
    /// has pinched in doesn't get yanked back to fit on rotation, but a user
    /// who hasn't zoomed still sees the whole puzzle after the bounds change.
    private var isFitToScreen = true
    /// Last bounds size we laid out at. Used to detect real size changes
    /// (rotation, split view, keyboard, etc.) vs. no-op layout passes.
    private var lastLaidOutSize: CGSize = .zero

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
        imageView.onTapRegions = { [weak coordinator] regionIds in
            coordinator?.onTapRegions(regionIds)
        }
        canvasSize = CGSize(
            width: puzzle.workingWidth * 8,
            height: puzzle.workingHeight * 8
        )
        imageView.frame = CGRect(origin: .zero, size: canvasSize)
        contentSize = canvasSize
        addSubview(imageView)
    }

    func update(
        progress: PuzzleProgress,
        puzzle: PuzzleMetadata,
        highlightedColorIndex: Int?,
        largeBrushEnabled: Bool
    ) {
        imageView.update(
            progress: progress,
            puzzle: puzzle,
            highlightedColorIndex: highlightedColorIndex,
            largeBrushEnabled: largeBrushEnabled
        )
    }

    func redraw(
        progress: PuzzleProgress,
        puzzle: PuzzleMetadata,
        highlightedColorIndex: Int?,
        largeBrushEnabled: Bool
    ) {
        imageView.update(
            progress: progress,
            puzzle: puzzle,
            highlightedColorIndex: highlightedColorIndex,
            largeBrushEnabled: largeBrushEnabled
        )
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImageView()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        // Re-rasterize the canvas at the new zoom scale so numbers and region
        // outlines stay crisp instead of being scaled-up bitmap pixels.
        updateImageContentScale()
        // If the user ended the pinch back at (or below) the fit scale, treat
        // the canvas as fitted again so future resizes keep the whole puzzle
        // visible. Any zoom in past fit flips this off.
        isFitToScreen = scale <= minimumZoomScale + 0.001
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateMinimumZoomScaleForSize(bounds.size)
        if !hasAppliedInitialZoom, bounds.width > 0, bounds.height > 0, canvasSize != .zero {
            zoomScale = minimumZoomScale
            hasAppliedInitialZoom = true
            isFitToScreen = true
            updateImageContentScale()
        } else if hasAppliedInitialZoom,
                  isFitToScreen,
                  bounds.size != lastLaidOutSize,
                  bounds.width > 0,
                  bounds.height > 0 {
            // Bounds changed (rotation, split view, etc.) and the user was
            // still at fit-to-screen — re-apply the fit zoom so the canvas
            // doesn't overflow the new bounds (previously `zoomScale` only
            // clamped *up* to the new minimum, so shrinking the height left
            // the canvas taller than the visible area).
            zoomScale = minimumZoomScale
            updateImageContentScale()
        }
        lastLaidOutSize = bounds.size
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
    // Tuned to catch nearby freeform blobs around a child's finger without
    // jumping across clearly separate shapes; freeform regions are already
    // chunkier than square-grid cells, so this stays intentionally modest.
    private static let freeformBrushRadius = 6

    private static func squareGridBrushRadius(forCellSize cellSize: Int) -> Int {
        // Half a cell plus one working pixel reaches over the tapped square's
        // edge into its immediate neighbors without jumping several cells away
        // in one stroke; for example, cellSize 8 becomes a radius of 5.
        max(1, cellSize / 2 + 1)
    }

    private var puzzle: PuzzleMetadata?
    private var regionIds: [Int] = []
    private var lastProgress: PuzzleProgress?
    /// Color index whose unfilled regions should be tinted a very light grey
    /// as a hint to the player. `nil` disables the hint.
    private var highlightedColorIndex: Int?
    /// Most recent pan sample location (in this view's coordinate space). We
    /// keep it so a fast swipe can be interpolated between callbacks — the
    /// pan recognizer only fires at display-refresh rate, so without
    /// interpolation a finger moving across ~5 cells per frame would have
    /// cells in the middle of each step silently skipped.
    private var lastSwipedPoint: CGPoint?
    /// Regions already emitted during the current swipe so the finger can move
    /// around inside one painted area without re-delivering it every frame.
    private var swipedRegionIds: Set<Int> = []
    private var largeBrushEnabled = false
    var onTapRegions: ([Int]) -> Void = { _ in }

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

    func update(
        progress: PuzzleProgress,
        puzzle: PuzzleMetadata,
        highlightedColorIndex: Int?,
        largeBrushEnabled: Bool
    ) {
        self.puzzle = puzzle
        self.lastProgress = progress
        self.highlightedColorIndex = highlightedColorIndex
        self.largeBrushEnabled = largeBrushEnabled
        setNeedsDisplay()
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        deliverRegionIds(atPoint: recognizer.location(in: self))
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let point = recognizer.location(in: self)
        switch recognizer.state {
        case .began:
            swipedRegionIds.removeAll(keepingCapacity: true)
            lastSwipedPoint = point
            deliverRegionIds(atPoint: point, dedupe: true)
        case .changed:
            // Walk from the previous pan sample to the current one in small
            // steps so a fast swipe covers every cell the finger actually
            // crossed, not just the ones sampled at display-refresh rate.
            deliverRegionsAlongSegment(from: lastSwipedPoint ?? point, to: point)
            lastSwipedPoint = point
        case .ended, .cancelled, .failed:
            swipedRegionIds.removeAll(keepingCapacity: true)
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
            deliverRegionIds(atPoint: end, dedupe: true)
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
            deliverRegionIds(atPoint: end, dedupe: true)
            return
        }
        let steps = max(1, Int((distance / stepLength).rounded(.up)))
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let p = CGPoint(x: start.x + dx * t, y: start.y + dy * t)
            deliverRegionIds(atPoint: p, dedupe: true)
        }
    }

    /// Finds the region(s) under `point` and (unless already delivered this
    /// swipe) forwards them to `onTapRegions`. `dedupe` keeps the pan gesture from
    /// firing continuously while the finger is inside a single region.
    private func deliverRegionIds(atPoint point: CGPoint, dedupe: Bool = false) {
        guard let puzzle, !puzzle.regions.isEmpty else { return }
        guard bounds.contains(point) else {
            if dedupe { swipedRegionIds.removeAll(keepingCapacity: true) }
            return
        }
        let pixelPoint = PixelPoint(
            x: Int((point.x / bounds.width) * CGFloat(puzzle.workingWidth)),
            y: Int((point.y / bounds.height) * CGFloat(puzzle.workingHeight))
        )
        let brushRadius: Int = {
            guard largeBrushEnabled else { return 0 }
            switch puzzle.strategy {
            case .squareGrid(let cellSize):
                return Self.squareGridBrushRadius(forCellSize: cellSize)
            case .freeformRegions:
                // Freeform regions can be irregular, so use a small fixed
                // radius that catches nearby blobs without leaping too far.
                return Self.freeformBrushRadius
            }
        }()
        let touchedRegionIds = PuzzleBrush.regionIds(
            around: pixelPoint,
            brushRadius: brushRadius,
            in: puzzle
        )
        guard !touchedRegionIds.isEmpty else { return }
        let regionIdsToDeliver: [Int]
        if dedupe {
            regionIdsToDeliver = touchedRegionIds.filter { swipedRegionIds.insert($0).inserted }
        } else {
            regionIdsToDeliver = touchedRegionIds
        }
        guard !regionIdsToDeliver.isEmpty else { return }
        onTapRegions(regionIdsToDeliver)
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
                // "See color blocks" hint: paint the background of every
                // unfilled cell belonging to the currently-selected color
                // in a very light grey, so the shape of the next color
                // pops visually without giving away the final color.
                if let highlighted = highlightedColorIndex, region.colorIndex == highlighted {
                    ctx.setFillColor(UIColor(white: 0.90, alpha: 1).cgColor)
                    ctx.fill(rect)
                }
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
