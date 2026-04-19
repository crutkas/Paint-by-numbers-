import SwiftUI
import UIKit
import PBNCore

struct RootView: View {
    @EnvironmentObject var library: PuzzleLibrary
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            LibraryView()
                .navigationDestination(for: UUID.self) { puzzleId in
                    if let meta = library.puzzles.first(where: { $0.id == puzzleId }) {
                        PlayView(puzzle: meta)
                    } else {
                        Text("Puzzle not found").padding()
                    }
                }
                .navigationDestination(for: PendingImageWrapper.self) { wrapper in
                    NewPuzzleView(sourceImage: wrapper.image, path: $path)
                        .environmentObject(library)
                }
        }
        // Pushing the new-puzzle page (instead of presenting a sheet) keeps
        // it inside the normal navigation stack, so the user can get a full
        // screen of pixelated preview and swipe back like any other page.
        .onReceive(library.$pendingImportImage) { newValue in
            guard let image = newValue else { return }
            path.append(PendingImageWrapper(image: image))
            // Consume the pending image immediately so returning to this
            // screen later doesn't auto-push a second setup page.
            library.pendingImportImage = nil
        }
    }
}

/// Identity wrapper for an incoming `UIImage` so it can be used as a value
/// on a `NavigationStack` path. `UIImage` itself is not `Hashable`, so we
/// key the destination on a per-import UUID.
struct PendingImageWrapper: Identifiable, Hashable {
    let id = UUID()
    let image: UIImage

    static func == (lhs: PendingImageWrapper, rhs: PendingImageWrapper) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
