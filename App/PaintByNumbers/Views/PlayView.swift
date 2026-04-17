import SwiftUI
import PBNCore

/// Playing the puzzle. Presents the canvas + a palette strip (bottom on
/// iPhone, side on iPad). The canvas uses `PuzzleCanvasView`, a UIKit-backed
/// view that draws regions and handles tap-to-fill efficiently.
struct PlayView: View {
    let puzzle: PuzzleMetadata

    @EnvironmentObject var library: PuzzleLibrary
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var progress: PuzzleProgress
    @State private var selectedColorIndex: Int = 0
    @State private var showCompletion = false

    init(puzzle: PuzzleMetadata) {
        self.puzzle = puzzle
        _progress = State(initialValue: PuzzleProgress(puzzleId: puzzle.id))
    }

    var body: some View {
        Group {
            if sizeClass == .regular {
                HStack(spacing: 0) {
                    canvas
                    palette
                        .frame(width: 120)
                }
            } else {
                VStack(spacing: 0) {
                    canvas
                    palette
                        .frame(height: 100)
                }
            }
        }
        .navigationTitle(puzzle.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ProgressView(
                    value: PuzzleProgressCalculator.completion(progress: progress, puzzle: puzzle)
                )
                .frame(width: 120)
            }
        }
        .onAppear {
            progress = library.progress(for: puzzle.id)
        }
        .onChange(of: progress) { _, newValue in
            library.save(progress: newValue)
            if PuzzleProgressCalculator.isComplete(progress: newValue, puzzle: puzzle) {
                showCompletion = true
            }
        }
        .sheet(isPresented: $showCompletion) {
            CompletionView(puzzle: puzzle, progress: progress)
                .environmentObject(library)
        }
    }

    private var canvas: some View {
        PuzzleCanvasView(
            puzzle: puzzle,
            progress: $progress,
            selectedColorIndex: $selectedColorIndex
        )
        .background(Color(.systemBackground))
    }

    private var palette: some View {
        PaletteStripView(
            puzzle: puzzle,
            progress: progress,
            selectedColorIndex: $selectedColorIndex,
            axis: sizeClass == .regular ? .vertical : .horizontal
        )
        .background(Color(.secondarySystemBackground))
    }
}
