# Codebase Structure

**Analysis Date:** 2026-10-19

## Directory Layout

```
HyperVideo Converter/
├── Package.swift                 # SwiftPM manifest (macOS 26, tools 6.2)
├── Sources/
│   ├── HyperVideoCore/           # UI-free library
│   │   ├── Models/               # Value types: settings, presets, jobs, estimates
│   │   └── Engine/               # AVFoundation transcoding, inspection, filters
│   │       └── Matroska/         # EBML/MKV writer + remuxer
│   └── HyperVideoConverter/      # SwiftUI executable
│       ├── App/                  # @main app, delegate, commands, quit flow
│       ├── Stores/               # @Observable models and persistence
│       ├── Views/                # SwiftUI views
│       │   ├── Components/       # Theme, shared settings controls
│       │   ├── Inspector/        # Output inspector panel
│       │   ├── Pages/            # History, Favorites, Analyze pages
│       │   └── Workspace/        # Conversion list, drop zone, bottom bar
│       └── Resources/            # pt-BR.lproj localization
├── Tests/
│   ├── HyperVideoCoreTests/      # Engine/model tests (incl. integration, stress)
│   └── HyperVideoConverterTests/ # Store/app logic tests
├── Resources/                    # Info.plist, AppIcon.png (bundling)
└── Scripts/                      # build-app.sh, make-icon.swift
```

## Directory Purposes

**`Sources/HyperVideoCore/Models`:** `EncodeSettings.swift`, `Preset.swift`, `HandBrakePresets.swift`, `Job.swift`, `MediaInfo.swift`, `SizePrediction.swift`, `Estimates.swift`, `Subtitles.swift`, `SubtitleFile.swift`.
**`Sources/HyperVideoCore/Engine`:** `TranscodeEngine.swift`, `PipelineFactory.swift`, `SamplePump.swift`, `OutputSettingsBuilder.swift`, `GeometryPlanner.swift`, `FilterCompositor.swift`, `SubtitleBurner.swift`, `MediaInspector.swift`, `FileBookmarks.swift`.
**`Sources/HyperVideoConverter/Stores`:** `AppModel.swift` split into `AppModel+Import/+Mode/+Workspace.swift`; `QueueStore.swift`, `PresetStore.swift`, `Persistence.swift`, `CoalescingSaver.swift`, `Notifier.swift`, `UIState.swift`.
**`Sources/HyperVideoConverter/Views`:** top-level `ContentView.swift`, `SidebarView.swift`, settings tabs (`SettingsTabs.swift`, `DimensionsAudioTabs.swift`, `TrimTab.swift`, `SubtitlesTab.swift`), sheets.

## Key File Locations

**Entry Points:**
- `Sources/HyperVideoConverter/App/HyperVideoConverterApp.swift`: app entry
- `Sources/HyperVideoCore/Engine/TranscodeEngine.swift`: encode entry

**Configuration:**
- `Package.swift`, `Resources/Info.plist`, `Scripts/build-app.sh`

**Testing:**
- `Tests/HyperVideoCoreTests/StressClip.swift`, `Tests/HyperVideoConverterTests/AppTestClip.swift`, `TestEnvironment.swift`: fixtures/helpers

## Naming Conventions

**Files:** PascalCase, one primary type per file (`QueueStore.swift`); extensions as `Type+Area.swift` (`AppModel+Import.swift`).
**Tests:** `<Subject>Tests.swift`.
**Directories:** PascalCase by role.
**Size:** keep files under ~400 lines (largest is `QueueStore.swift`, 370).

## Where to Add New Code

**New encode feature:** model in `Sources/HyperVideoCore/Models/`, logic in `Sources/HyperVideoCore/Engine/`; tests in `Tests/HyperVideoCoreTests/`.
**New app state/behavior:** `Sources/HyperVideoConverter/Stores/` (new `AppModel+X.swift` extension if it extends AppModel); tests in `Tests/HyperVideoConverterTests/`.
**New UI:** pages → `Views/Pages/`, inspector → `Views/Inspector/`, list/workspace → `Views/Workspace/`, reusable controls → `Views/Components/`.
**Strings:** add pt-BR translations in `Sources/HyperVideoConverter/Resources/pt-BR.lproj` (checked by `LocalizationTests.swift`).

## Special Directories

**`.build`, `.build-xcode`, `build`, `dist`:** build outputs — Generated: Yes, Committed: No.
**`.planning`:** GSD planning docs — Committed: Yes.

---

*Structure analysis: 2026-10-19*
