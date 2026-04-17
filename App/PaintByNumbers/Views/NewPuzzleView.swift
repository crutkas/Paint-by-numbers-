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
    @State private var cellSize: Double = 8
    @State private var isGenerating = false

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

                    Toggle("Chunky square cells", isOn: $useSquareGrid)
                        .accessibilityHint("Turn on for big square cells that are easy to paint. Turn off for free-form shapes.")

                    if useSquareGrid {
                        VStack(alignment: .leading) {
                            Text("Cell size: \(Int(cellSize))")
                                .font(.system(.subheadline, design: .rounded))
                            Slider(value: $cellSize, in: 3...20, step: 1)
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
