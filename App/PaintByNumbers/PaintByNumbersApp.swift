import SwiftUI
import PBNCore

@main
struct PaintByNumbersApp: App {
    @StateObject private var library = PuzzleLibrary()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .onOpenURL { url in
                    library.handleIncomingURL(url)
                }
                // iPad drag-and-drop of images onto the app window.
                .onDrop(of: [.image], isTargeted: nil) { providers in
                    library.handleDroppedProviders(providers)
                    return true
                }
        }
    }
}
