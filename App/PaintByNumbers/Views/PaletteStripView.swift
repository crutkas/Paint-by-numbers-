import SwiftUI
import PBNCore

/// Horizontal / vertical palette strip. Each color chip shows the 1-based
/// number and how many regions remain to paint in that color. Kid-friendly
/// large hit targets (min 56pt).
struct PaletteStripView: View {
    let puzzle: PuzzleMetadata
    let progress: PuzzleProgress
    @Binding var selectedColorIndex: Int
    let axis: Axis

    var body: some View {
        ScrollView(axis == .horizontal ? .horizontal : .vertical, showsIndicators: false) {
            layout {
                ForEach(puzzle.palette.colors.indices, id: \.self) { index in
                    chip(for: index)
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private func layout<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if axis == .horizontal {
            HStack(spacing: 12) { content() }
        } else {
            VStack(spacing: 12) { content() }
        }
    }

    private func chip(for index: Int) -> some View {
        let color = puzzle.palette.colors[index]
        let swiftUIColor = Color(
            red: Double(color.r) / 255,
            green: Double(color.g) / 255,
            blue: Double(color.b) / 255
        )
        let remaining = PuzzleProgressCalculator.remainingRegionIds(
            forColor: index, puzzle: puzzle, progress: progress
        ).count
        let numberColor: Color = color.luminance > 0.5 ? .black : .white
        let isSelected = selectedColorIndex == index
        let isDone = remaining == 0

        return Button {
            selectedColorIndex = index
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(swiftUIColor)
                VStack(spacing: 2) {
                    Text("\(index + 1)")
                        .font(.system(.title3, design: .rounded, weight: .black))
                        .foregroundStyle(numberColor)
                    if !isDone {
                        Text("\(remaining)")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(numberColor.opacity(0.8))
                    } else {
                        Image(systemName: "checkmark")
                            .font(.caption.bold())
                            .foregroundStyle(numberColor)
                    }
                }
            }
            .frame(width: 56, height: 56)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 4)
            )
            .opacity(isDone ? 0.5 : 1)
        }
        .accessibilityLabel("Color \(index + 1)")
        .accessibilityValue(isDone ? "Done" : "\(remaining) regions left")
        .buttonStyle(.plain)
    }
}
