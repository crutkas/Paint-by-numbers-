import SwiftUI
import PhotosUI
import PBNCore

/// Library / home screen: shows saved puzzles and the three big import buttons.
/// Designed with big, rounded, high-contrast UI for 6-10 year-olds.
struct LibraryView: View {
    @EnvironmentObject var library: PuzzleLibrary

    @State private var photosPickerItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var showCamera = false
    @State private var showSettings = false

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                importButtons

                if library.puzzles.isEmpty {
                    emptyState
                } else {
                    Text("My Pictures")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .padding(.horizontal)

                    LazyVGrid(columns: columns, spacing: 16) {
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

    private var importButtons: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                PhotosPicker(
                    selection: $photosPickerItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    BigActionTile(
                        title: "Photos",
                        systemImage: "photo.on.rectangle.angled",
                        tint: .purple
                    )
                }

                Button {
                    showCamera = true
                } label: {
                    BigActionTile(
                        title: "Camera",
                        systemImage: "camera.fill",
                        tint: .pink
                    )
                }
            }
            Button {
                showFileImporter = true
            } label: {
                BigActionTile(
                    title: "Files",
                    systemImage: "folder.fill",
                    tint: .teal
                )
            }
        }
        .padding(.horizontal)
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

private struct BigActionTile: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
            Text(title)
                .font(.system(.title3, design: .rounded, weight: .bold))
        }
        .frame(maxWidth: .infinity, minHeight: 110)
        .foregroundStyle(.white)
        .background(tint.gradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("New puzzle from \(title)")
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
