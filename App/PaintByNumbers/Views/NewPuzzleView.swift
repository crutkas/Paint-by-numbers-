import SwiftUI
import UIKit
import CoreGraphics
import PBNCore

/// New-puzzle setup page: preview the picked image with a live pixelated
/// preview and pick the grid size before generating. It's a pushed page
/// (not a modal sheet) so it feels like part of the app rather than a
/// one-shot dialog, and the whole screen has room for a big preview that
/// updates as the user drags the grid slider.
struct NewPuzzleView: View {
    let sourceImage: UIImage

    @EnvironmentObject var library: PuzzleLibrary
    @Environment(\.dismiss) private var dismiss

    @State private var title = "My Puzzle"
    @State private var gridSize: Double = 24
    @State private var isGenerating = false
    /// Cached RGB representation of the source image so the live preview
    /// doesn't re-decode the UIImage on every slider tick.
    @State private var baseRGB: RGBImage?

    /// Grid size is in cells along the long edge of the image — from a chunky
    /// 8-across "graph paper" down to a fine 64-across grid.
    private let minGrid: Double = 8
    private let maxGrid: Double = 64

    /// The working-image resolution used during puzzle generation. We keep a
    /// single fixed preset instead of a "difficulty" picker — grid size is
    /// the only knob the user sees.
    private let workingLongEdge: Int = Difficulty.medium.workingLongEdge
    private let paletteDifficulty: Difficulty = .medium

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                preview
                    .aspectRatio(sourceAspect, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.secondary.opacity(0.25), lineWidth: 1)
                    )
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Name")
                        .font(.system(.headline, design: .rounded))
                    TextField("My Puzzle", text: $title)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.title3, design: .rounded))
                }
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Grid size")
                            .font(.system(.headline, design: .rounded))
                        Spacer()
                        Text("\(previewCells.width) × \(previewCells.height) squares")
                            .font(.system(.subheadline, design: .rounded).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $gridSize, in: minGrid...maxGrid, step: 1)
                        .accessibilityHint("Drag to change how many squares are in the grid.")
                }
                .padding(.horizontal)

                Button {
                    Task { await generate() }
                } label: {
                    HStack {
                        if isGenerating { ProgressView() }
                        Text(isGenerating ? "Making puzzle…" : "Start painting!")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isGenerating)
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("New Puzzle")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if baseRGB == nil {
                baseRGB = sourceImage.rgbImage()
            }
        }
    }

    // MARK: - Preview

    private var sourceAspect: CGFloat {
        let size = sourceImage.size
        guard size.width > 0, size.height > 0 else { return 1 }
        return size.width / size.height
    }

    /// Grid dimensions used for the live preview, preserving the source
    /// image's aspect ratio. The long edge always has `gridSize` cells.
    private var previewCells: (width: Int, height: Int) {
        let long = max(1, Int(gridSize))
        let w = sourceImage.size.width
        let h = sourceImage.size.height
        guard w > 0, h > 0 else { return (long, long) }
        if w >= h {
            let short = max(1, Int(((Double(h) / Double(w)) * Double(long)).rounded()))
            return (long, short)
        } else {
            let short = max(1, Int(((Double(w) / Double(h)) * Double(long)).rounded()))
            return (short, long)
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let pixelated = pixelatedPreview() {
            Image(uiImage: pixelated)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
        } else {
            Image(uiImage: sourceImage)
                .resizable()
                .scaledToFit()
        }
    }

    /// Down-samples the source image to `previewCells` using nearest-neighbor
    /// sampling so the preview shows exactly the pixelation the generated
    /// puzzle will have. Returns `nil` (and the caller falls back to the
    /// original image) if we can't build an RGB representation yet.
    private func pixelatedPreview() -> UIImage? {
        guard let rgb = baseRGB else { return nil }
        let cells = previewCells
        let downscaled = rgb.nearestNeighborScaled(
            toWidth: cells.width,
            height: cells.height
        )
        return uiImage(from: downscaled)
    }

    /// Builds an opaque `UIImage` from an `RGBImage` without any filtering,
    /// so SwiftUI's `.interpolation(.none)` can blow it up into visible
    /// pixel blocks for the preview.
    private func uiImage(from rgb: RGBImage) -> UIImage? {
        let w = rgb.width
        let h = rgb.height
        guard w > 0, h > 0, rgb.pixels.count == w * h else { return nil }
        let bytesPerRow = w * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * h)
        for y in 0..<h {
            for x in 0..<w {
                let c = rgb.pixels[y * w + x]
                let i = y * bytesPerRow + x * 4
                bytes[i] = c.r
                bytes[i + 1] = c.g
                bytes[i + 2] = c.b
                bytes[i + 3] = 255
            }
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let ctx = bytes.withUnsafeMutableBytes { buf -> CGContext? in
            CGContext(
                data: buf.baseAddress,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )
        }
        guard let cg = ctx?.makeImage() else { return nil }
        return UIImage(cgImage: cg)
    }

    // MARK: - Generate

    private func generate() async {
        isGenerating = true
        defer { isGenerating = false }
        // Convert grid size (cells along the long edge) into a working-pixel
        // cell size for the generator. Using the fixed working long edge as
        // the reference means the generated puzzle has ~`gridSize` cells on
        // its long edge, matching the preview the user just dragged.
        let cellSize = max(1, Int((Double(workingLongEdge) / gridSize).rounded()))
        let strategy: GridStrategy = .squareGrid(cellSize: cellSize)
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let meta = await library.createPuzzle(
            fromImage: sourceImage,
            title: trimmed.isEmpty ? "My Puzzle" : trimmed,
            difficulty: paletteDifficulty,
            strategy: strategy
        )
        if meta != nil {
            library.pendingImportImage = nil
            dismiss()
        }
    }
}
