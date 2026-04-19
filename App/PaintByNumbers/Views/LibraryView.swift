import SwiftUI
import PhotosUI
import PBNCore

/// Library / home screen: shows saved puzzles with the three import
/// options (Photos / Camera / Files) pinned to the bottom-right as a
/// floating top-layer overlay. Designed with big, rounded, high-contrast
/// UI for 6-10 year-olds.
struct LibraryView: View {
    @EnvironmentObject var library: PuzzleLibrary

    @State private var photosPickerItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var showCamera = false
    @State private var showSettings = false

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 20)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if library.puzzles.isEmpty {
                    emptyState
                } else {
                    Text("My Pictures")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .padding(.horizontal)

                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(library.puzzles, id: \.id) { puzzle in
                            NavigationLink(value: puzzle.id) {
                                PuzzleTile(puzzle: puzzle)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
            // Leave room at the bottom so the floating import buttons
            // don't cover the last row of tiles when scrolled to the end.
            // The stack is ~3 × 48pt buttons with spacing, so reserve a
            // taller inset than a single FAB would need.
            .padding(.bottom, 220)
        }
        // Three import options pinned to the bottom-right as a floating
        // top layer, stacked vertically. Mirrors the new-puzzle page's
        // control panel style (all options visible at once) while keeping
        // the home screen clean, since the buttons overlay the grid
        // instead of taking up their own row.
        .overlay(alignment: .bottomTrailing) {
            importButtons
                .padding(.trailing, 20)
                .padding(.bottom, 20)
        }
        .navigationTitle("Paint by Numbers")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.title2)
                }
                .accessibilityLabel("Settings")
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showCamera) {
            CameraPicker { image in
                library.pendingImportImage = image
                showCamera = false
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                if url.startAccessingSecurityScopedResource() {
                    defer { url.stopAccessingSecurityScopedResource() }
                    if let data = try? Data(contentsOf: url),
                       let image = UIImage(data: data) {
                        library.pendingImportImage = image
                    }
                }
            }
        }
        .onChange(of: photosPickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    library.pendingImportImage = image
                }
                photosPickerItem = nil
            }
        }
    }

    /// Bottom-right floating stack of the three import options. Always
    /// shown at the same time (no "+" expand/collapse) so each choice is
    /// one tap away, while the overlay positioning keeps them layered on
    /// top of the puzzle grid rather than pushing content down.
    private var importButtons: some View {
        VStack(alignment: .trailing, spacing: 14) {
            FABSubAction(
                title: "Files",
                systemImage: "folder.fill",
                tint: .teal
            ) {
                showFileImporter = true
            }

            FABSubAction(
                title: "Camera",
                systemImage: "camera.fill",
                tint: .pink
            ) {
                showCamera = true
            }

            // Photos uses a PhotosPicker, which must stay in the view
            // tree for its binding to drive the presentation. Wrap the
            // FAB sub-action as its label so it matches the other two
            // options visually.
            PhotosPicker(
                selection: $photosPickerItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                FABSubActionLabel(
                    title: "Photos",
                    systemImage: "photo.on.rectangle.angled",
                    tint: .purple
                )
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "paintpalette.fill")
                .font(.system(size: 72))
                .foregroundStyle(.tint)
            Text("Pick a picture to get started!")
                .font(.system(.headline, design: .rounded))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

/// Label used by every secondary FAB: a small circular colored icon with a
/// pill-shaped title chip to its left, so each option is both tappable and
/// self-describing at a glance.
private struct FABSubActionLabel: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)

            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(tint.gradient, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                .shadow(color: tint.opacity(0.35), radius: 6, y: 3)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("New puzzle from \(title)")
    }
}

/// Tappable wrapper around `FABSubActionLabel` for plain-button callers.
private struct FABSubAction: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            FABSubActionLabel(title: title, systemImage: systemImage, tint: tint)
        }
        .buttonStyle(.plain)
    }
}

private struct PuzzleTile: View {
    let puzzle: PuzzleMetadata
    @EnvironmentObject var library: PuzzleLibrary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                thumbnail
                    .frame(height: 140)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.secondary.opacity(0.25), lineWidth: 1)
                    )

                Text("\(Int(completion * 100))%")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(6)
            }

            Text(puzzle.title)
                .font(.system(.headline, design: .rounded))
                .lineLimit(1)
        }
        .contextMenu {
            Button(role: .destructive) {
                library.deletePuzzle(puzzle.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var completion: Double {
        let progress = library.progress(for: puzzle.id)
        return PuzzleProgressCalculator.completion(progress: progress, puzzle: puzzle)
    }

    @ViewBuilder
    private var thumbnail: some View {
        let sourceURL = library.store.puzzleDirectory(id: puzzle.id)
            .appendingPathComponent(puzzle.sourceImageFilename)
        if let data = try? Data(contentsOf: sourceURL), let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            Rectangle().fill(.gray.opacity(0.2))
                .overlay(Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary))
        }
    }
}
