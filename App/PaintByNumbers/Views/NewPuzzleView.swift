import SwiftUI
import PBNCore

/// New-puzzle setup screen: preview the picked image and pick a difficulty
/// and grid strategy before generating.
struct NewPuzzleView: View {
    let sourceImage: UIImage
    let onDismiss: () -> Void

    @EnvironmentObject var library: PuzzleLibrary
    @Environment(\.dismiss) private var dismiss

    @State private var title = "My Puzzle"
    @State private var difficulty: Difficulty = .medium
    @State private var useSquareGrid = true
    @State private var cellSize: Double = 24
    @State private var isGenerating = false

    /// Upper bound for the cell-size slider. Half the working image's long
    /// edge (per the chosen difficulty) — big enough to produce the chunkiest
    /// puzzle that still has more than one region.
    private var maxCellSize: Double {
        Double(difficulty.workingLongEdge) / 2
    }

    /// Lower bound for the cell-size slider. The previous slider maxed out at
    /// 16, which testers said was still way too fine for young kids — so 16
    /// is now the floor.
    private let minCellSize: Double = 16

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Image(uiImage: sourceImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Section("Name") {
                    TextField("My Puzzle", text: $title)
                        .font(.system(.title3, design: .rounded))
                }

                Section("How tricky?") {
                    Picker("Difficulty", selection: $difficulty) {
                        Text("Easy").tag(Difficulty.easy)
                        Text("Medium").tag(Difficulty.medium)
                        Text("Hard").tag(Difficulty.hard)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: difficulty) { _, _ in
                        // Difficulty changes the working image size, which in
                        // turn changes the allowed cell-size range. Clamp so
                        // the slider handle can't fall off the end.
                        cellSize = min(max(cellSize, minCellSize), maxCellSize)
                    }

                    Toggle("Chunky square cells", isOn: $useSquareGrid)
                        .accessibilityHint("Turn on for big square cells that are easy to paint. Turn off for free-form shapes.")

                    if useSquareGrid {
                        VStack(alignment: .leading) {
                            Text("Cell size: \(Int(cellSize))")
                                .font(.system(.subheadline, design: .rounded))
                            Slider(
                                value: $cellSize,
                                in: minCellSize...max(minCellSize, maxCellSize),
                                step: 1
                            )
                        }
                    }
                }

                Section {
                    Button {
                        Task { await generate() }
                    } label: {
                        HStack {
                            if isGenerating { ProgressView() }
                            Text(isGenerating ? "Making puzzle…" : "Start painting!")
                                .font(.system(.title3, design: .rounded, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isGenerating)
                }
            }
            .navigationTitle("New Puzzle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                        onDismiss()
                    }
                }
            }
        }
    }

    private func generate() async {
        isGenerating = true
        defer { isGenerating = false }
        let strategy: GridStrategy = useSquareGrid
            ? .squareGrid(cellSize: max(1, Int(cellSize)))
            : .freeformRegions
        let meta = await library.createPuzzle(
            fromImage: sourceImage,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "My Puzzle" : title,
            difficulty: difficulty,
            strategy: strategy
        )
        if meta != nil {
            dismiss()
            onDismiss()
        }
    }
}
