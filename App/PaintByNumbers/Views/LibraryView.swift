import SwiftUI
import PhotosUI
import PBNCore

/// Library / home screen: shows saved puzzles and the bottom-right
/// floating action button that expands into the three import options.
/// Designed with big, rounded, high-contrast UI for 6-10 year-olds.
struct LibraryView: View {
    @EnvironmentObject var library: PuzzleLibrary

    @State private var photosPickerItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var showCamera = false
    @State private var showSettings = false
    /// Whether the bottom-right "+" FAB is expanded to show its import
    /// sub-actions. iOS-style: tap the primary button and the secondary
    /// options fan out above it.
    @State private var isFABExpanded = false

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
            // Leave room at the bottom so the FAB doesn't cover the last
            // row of tiles when scrolled to the end.
            .padding(.bottom, 96)
        }
        // iOS-style floating action button pinned to the bottom-right. The
        // primary "+" expands into Photos / Camera / Files sub-actions so
        // the home page stays clean while still giving one-tap access to
        // every import route.
        .overlay(alignment: .bottomTrailing) {
            importFAB
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

    /// Bottom-right floating action button that expands into the three
    /// import options. Sub-FABs stack above the primary button and each
    /// one animates in with a slight delay for a playful fan-out feel.
    private var importFAB: some View {
        VStack(alignment: .trailing, spacing: 14) {
            if isFABExpanded {
                FABSubAction(
                    title: "Files",
                    systemImage: "folder.fill",
                    tint: .teal
                ) {
                    collapseFAB()
                    showFileImporter = true
                }
                .transition(fabTransition)

                FABSubAction(
                    title: "Camera",
                    systemImage: "camera.fill",
                    tint: .pink
                ) {
                    collapseFAB()
                    showCamera = true
                }
                .transition(fabTransition)

                // Photos uses a PhotosPicker, which must stay in the view
                // tree for its binding to drive the presentation. Wrap
                // the FAB sub-action as its label so it still feels like
                // the other two options from the user's perspective.
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
                .simultaneousGesture(TapGesture().onEnded { collapseFAB() })
                .transition(fabTransition)
            }

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    isFABExpanded.toggle()
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Color.accentColor.gradient, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                    .rotationEffect(.degrees(isFABExpanded ? 45 : 0))
            }
            .accessibilityLabel(isFABExpanded ? "Close new puzzle menu" : "New puzzle")
        }
    }

    private var fabTransition: AnyTransition {
        .move(edge: .bottom).combined(with: .opacity)
    }

    private func collapseFAB() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            isFABExpanded = false
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
