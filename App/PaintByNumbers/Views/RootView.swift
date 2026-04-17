import SwiftUI
import PBNCore

struct RootView: View {
    @EnvironmentObject var library: PuzzleLibrary

    var body: some View {
        NavigationStack {
            LibraryView()
                .navigationDestination(for: UUID.self) { puzzleId in
                    if let meta = library.puzzles.first(where: { $0.id == puzzleId }) {
                        PlayView(puzzle: meta)
                    } else {
                        Text("Puzzle not found").padding()
                    }
                }
        }
        .sheet(item: Binding(
            get: { library.pendingImportImage.map(PendingImageWrapper.init) },
            set: { _ in library.pendingImportImage = nil }
        )) { wrapper in
            NewPuzzleView(sourceImage: wrapper.image) {
                library.pendingImportImage = nil
            }
            .environmentObject(library)
        }
    }
}

struct PendingImageWrapper: Identifiable {
    let id = UUID()
    let image: UIImage
}
