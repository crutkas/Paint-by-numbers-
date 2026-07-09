import SwiftUI
import UIKit
import Photos
import PBNCore

/// Shown when the user completes a puzzle. Offers Save-to-Photos, Share, and
/// Back-to-Library. A simple confetti-flavored animation celebrates the win.
struct CompletionView: View {
    let puzzle: PuzzleMetadata
    let progress: PuzzleProgress
    let regionIds: [Int]
    @Environment(\.dismiss) private var dismiss

    @State private var rendered: UIImage?
    @State private var shareItem: UIImage?
    @State private var saveResult: SaveResult?

    enum SaveResult: Identifiable {
        case success, failed(String)
        var id: String {
            switch self {
            case .success: return "success"
            case .failed(let msg): return "failed:\(msg)"
            }
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            Text("You did it! 🎉")
                .font(.system(.largeTitle, design: .rounded, weight: .black))

            if let rendered {
                Image(uiImage: rendered)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(.secondary.opacity(0.2))
                    )
                    .padding(.horizontal)
            } else {
                ProgressView().frame(height: 200)
            }

            VStack(spacing: 12) {
                Button {
                    if let rendered { saveToPhotos(rendered) }
                } label: {
                    Label("Save to Photos", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(rendered == nil)

                Button {
                    shareItem = rendered
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(rendered == nil)

                Button("Back to My Pictures") { dismiss() }
                    .font(.system(.body, design: .rounded, weight: .semibold))
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding(.top, 40)
        .onAppear { render() }
        .sheet(item: Binding(
            get: { shareItem.map(ImageShareWrapper.init) },
            set: { _ in shareItem = nil }
        )) { wrapper in
            ShareSheet(items: [wrapper.image])
        }
        .alert(item: $saveResult) { result in
            switch result {
            case .success:
                return Alert(title: Text("Saved!"), message: Text("Check your Photos."))
            case .failed(let msg):
                return Alert(title: Text("Couldn't save"), message: Text(msg))
            }
        }
    }

    private func render() {
        guard let image = PuzzleRenderer.render(
            puzzle: puzzle,
            progress: progress,
            regionIds: regionIds
        ) else {
            saveResult = .failed("The puzzle's region map is missing or damaged.")
            return
        }
        self.rendered = image
    }

    private func saveToPhotos(_ image: UIImage) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { saveResult = .failed("Photo access was not granted.") }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    saveResult = success ? .success : .failed(error?.localizedDescription ?? "Unknown error")
                }
            }
        }
    }
}

private struct ImageShareWrapper: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
