# Paint by Numbers

A kid-friendly (ages 6–10) paint-by-numbers app for **iPhone** and **iPad**.
Pick a photo from **Photos**, **Files**, or the **Camera**, choose a difficulty
and grid style, and paint the numbered regions one color at a time. Puzzles
and progress are saved automatically; finished masterpieces can be saved to
Photos or shared. Images shared **into** the app from other apps become new
puzzles via the bundled Share Extension.

## Repository layout

```
.
├── Package.swift               Swift package manifest for PBNCore
├── project.yml                 XcodeGen spec for the iOS app + Share Extension
├── Sources/PBNCore/            Platform-agnostic PBN engine (Linux-compatible)
│   ├── RGBColor.swift
│   ├── RGBImage.swift
│   ├── SeededGenerator.swift
│   ├── KMeansQuantizer.swift       k-means++ color quantizer
│   ├── ConnectedComponents.swift   4-connected region labeling + merge
│   ├── PuzzleGenerator.swift       End-to-end generation pipeline
│   ├── PuzzleMetadata.swift        Codable models + progress helpers
│   ├── PuzzleStore.swift           Disk-backed metadata + progress store
│   └── ShareImport.swift           URL scheme + App-Group handoff payload
├── Tests/PBNCoreTests/         XCTest suite (48 tests) — runs on Linux
├── App/PaintByNumbers/         SwiftUI iOS/iPadOS app
│   ├── PaintByNumbersApp.swift     @main entry
│   ├── PuzzleLibrary.swift         ObservableObject backing the app
│   ├── AppGroup.swift              App Group container helpers
│   ├── UIImage+RGBImage.swift      UIImage ↔ PBNCore.RGBImage bridge
│   └── Views/                      Library, NewPuzzle, Play, Completion, Settings …
├── ShareExtension/             Share Extension target
│   └── ShareViewController.swift   Accepts an image, hands off via URL scheme
└── .github/workflows/ci.yml    GitHub Actions — Linux tests + macOS iOS build
```

The **PBNCore** library is deliberately platform-agnostic (no `UIKit`,
`CoreGraphics`, `CoreImage`) so its XCTest suite runs on Linux CI and
verifies every piece of the paint-by-numbers algorithm on every push.

## Requirements

- iOS / iPadOS **17.0+** (single universal app)
- Xcode **15.4+**
- Swift **5.9+**
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build and run

```bash
# 1. Generate the Xcode project from project.yml (re-run after editing it).
xcodegen generate

# 2. Open and run.
open PaintByNumbers.xcodeproj
```

Select the **PaintByNumbers** scheme and an iPhone/iPad simulator, then ⌘R.

## Running the tests

### Linux / CI (fast, no Xcode needed)

```bash
swift test --parallel
```

This runs the entire `PBNCoreTests` suite (48 tests) against the PBN engine,
covering color math, image scaling, k-means quantization determinism and edge
cases, connected-components labeling and region merging, the full puzzle
generator, progress/completion calculation, on-disk puzzle store round-trips,
and share-import URL parsing.

### macOS / Xcode

```bash
xcodegen generate
xcodebuild \
  -project PaintByNumbers.xcodeproj \
  -scheme PaintByNumbers \
  -destination 'generic/platform=iOS Simulator' \
  build
# or run PBNCore tests alone:
swift test --parallel
```

## Continuous integration

GitHub Actions runs two jobs on every push and pull request (see
[`.github/workflows/ci.yml`](.github/workflows/ci.yml)):

| Job | Runner | What it does |
| --- | --- | --- |
| **PBNCore tests (Linux)** | `ubuntu-latest` | `swift build` + `swift test --parallel` for the PBN engine |
| **iOS build (macOS)** | `macos-14` | `brew install xcodegen`, `xcodegen generate`, `xcodebuild build` for the iOS Simulator, and `swift test` |

## Feature map

| Feature | Where |
| --- | --- |
| Universal iPhone + iPad layout | SwiftUI, `TARGETED_DEVICE_FAMILY 1,2` |
| Import from **Photos** | `PhotosPicker` in `LibraryView` |
| Import from **Files** | `.fileImporter(allowedContentTypes: [.image])` |
| Import from **Camera** | `CameraPicker` (`UIImagePickerController`) |
| Dynamic grid system | `Difficulty` + `GridStrategy` (square grid / freeform regions) |
| Color quantization | k-means++ in `KMeansQuantizer.swift` |
| Region generation | `ConnectedComponents.swift` with small-region merging |
| Save puzzle state | `PuzzleStore.saveProgress` / `loadProgress` |
| Save final image | `CompletionView` → `PHPhotoLibrary` |
| Share final image | `CompletionView` → `UIActivityViewController` |
| Share **into** the app | `PBNShareExtension` → App Group → `paintbynumbers://import?token=…` |
| Drag-and-drop import | `.onDrop(of: [.image])` on iPad |
| “Open in…” support | `CFBundleDocumentTypes` for `public.image` |

## Privacy

All image processing happens on device. No network calls are made with user
images. The app declares Photos and Camera usage strings in `Info.plist`.

## License

See [LICENSE](LICENSE).
