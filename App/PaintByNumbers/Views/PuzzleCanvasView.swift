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
            view.flashWrong(regionId: regionId)
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

    func configure(
        with puzzle: PuzzleMetadata,
        coordinator: PuzzleCanvasView.Coordinator
    ) {
        delegate = self
        minimumZoomScale = 1.0
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
        imageView.frame = CGRect(
            origin: .zero,
            size: CGSize(width: puzzle.workingWidth * 8, height: puzzle.workingHeight * 8)
        )
        contentSize = imageView.frame.size
        addSubview(imageView)
    }

    func update(progress: PuzzleProgress, puzzle: PuzzleMetadata) {
        imageView.update(progress: progress, puzzle: puzzle)
    }

    func redraw(progress: PuzzleProgress, puzzle: PuzzleMetadata) {
        imageView.update(progress: progress, puzzle: puzzle)
    }

    func flashWrong(regionId: Int) {
        imageView.flashWrong(regionId: regionId)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
}

/// Owns the rasterized canvas and the region-id hit-test map.
final class PuzzleImageView: UIView {
    private var puzzle: PuzzleMetadata?
    private var regionIds: [Int] = []
    private var lastProgress: PuzzleProgress?
    private var lastSwipedRegionId: Int?
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

    func flashWrong(regionId: Int) {
        let flash = UIView(frame: bounds)
        flash.backgroundColor = UIColor.systemRed.withAlphaComponent(0.25)
        flash.isUserInteractionEnabled = false
        addSubview(flash)
        UIView.animate(withDuration: 0.25, animations: {
            flash.alpha = 0
        }) { _ in
            flash.removeFromSuperview()
        }
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        deliverRegion(atPoint: recognizer.location(in: self))
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began, .changed:
            deliverRegion(atPoint: recognizer.location(in: self), dedupe: true)
        case .ended, .cancelled, .failed:
            lastSwipedRegionId = nil
        default:
            break
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
                let font = UIFont.systemFont(ofSize: max(8, min(rect.height, rect.width) * 0.6), weight: .semibold)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: UIColor.label
                ]
                let size = (number as NSString).size(withAttributes: attrs)
                let origin = CGPoint(
                    x: rect.midX - size.width / 2,
                    y: rect.midY - size.height / 2
                )
                (number as NSString).draw(at: origin, withAttributes: attrs)
            }
        }
    }
}
