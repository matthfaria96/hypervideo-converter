# Technology Stack

**Analysis Date:** 2026-10-19

## Languages

**Primary:**
- Swift 6 (tools version 6.2, Swift 6 language mode / strict concurrency) - all code in `Sources/` and `Tests/`

**Secondary:**
- zsh - build/packaging script `Scripts/build-app.sh`
- Swift script - icon generation `Scripts/make-icon.swift`

## Runtime

**Environment:**
- macOS 26+ (`platforms: [.macOS(.v26)]` in `Package.swift`; `LSMinimumSystemVersion` 26.0 in `Resources/Info.plist`, overwritten at build from `Package.swift`)
- Native arm64 app; local toolchain observed: Apple Swift 6.4

**Package Manager:**
- Swift Package Manager (`Package.swift`)
- Lockfile: not present (no external dependencies, so no `Package.resolved`)

## Frameworks

**Core:**
- SwiftUI + Observation (`@Observable`) - UI and state, `Sources/HyperVideoConverter/`
- AppKit - window/workspace integration (`NSWorkspace`, Finder reveal), `Sources/HyperVideoConverter/Stores/SystemIntegration.swift`
- AVFoundation / AVKit / CoreMedia / CoreAudioTypes - inspection, reading/writing, transcoding: `Sources/HyperVideoCore/Engine/TranscodeEngine.swift`, `SamplePump.swift`, `MediaInspector.swift`, `OutputSettingsBuilder.swift`, `PipelineFactory.swift`
- VideoToolbox - hardware encoder capabilities
- CoreImage (+ CIFilterBuiltins), CoreGraphics, CoreText - video filters and subtitle burn-in: `Engine/FilterCompositor.swift`, `Engine/FrameFilter.swift`, `Engine/SubtitleBurner.swift`
- Synchronization (`Mutex`/atomics) - thread-safe engine state
- UserNotifications - completion notifications, `Sources/HyperVideoConverter/Stores/Notifier.swift`
- QuickLook, UniformTypeIdentifiers - previews and file type handling
- OSLog - `Logger(subsystem: "com.hypervideo.converter", category: "app")` in `Stores/Persistence.swift`

**Custom (in-house, no third-party code):**
- Matroska/MKV writer and remuxer (EBML) - `Sources/HyperVideoCore/Engine/Matroska/` (`EBML.swift`, `MatroskaWriter.swift`, `MatroskaRemuxer.swift`, `MatroskaTrack.swift`, `AudioConfig.swift`)
- Subtitle parsing (SRT/timed text) - `Engine/SubtitleParser.swift`, `Engine/TimedText.swift`
- HandBrake preset import - `Models/HandBrakePresets.swift`

**Testing:**
- XCTest / Swift Testing via `swift test` - targets `HyperVideoCoreTests`, `HyperVideoConverterTests` in `Tests/`

**Build/Dev:**
- `swift build` (no Xcode project required)
- `Scripts/build-app.sh [release|debug]` - assembles `dist/HyperVideo Converter.app` + `.dmg`, copies `.lproj` localizations, sets version via PlistBuddy, codesigns, optional notarization
- `Scripts/make-icon.swift` - generates icon from `Resources/AppIcon.png`

## Key Dependencies

**Critical:**
- None external. Zero SwiftPM dependencies; everything relies on Apple system frameworks.

**Infrastructure:**
- `codesign`, `hdiutil`, `/usr/libexec/PlistBuddy`, `xcrun notarytool` / `stapler` (only when notarizing)

## Configuration

**Environment:**
- Runtime settings in `UserDefaults` (defaults registered in `Sources/HyperVideoConverter/App/HyperVideoConverterApp.swift`)
- Build env vars: `SIGN_IDENTITY` (default ad-hoc `-`), `NOTARY_PROFILE`
- Version from latest git tag (`vX.Y.Z`), build number from commit count

**Build:**
- `Package.swift` - targets: `HyperVideoCore` (library), `HyperVideoConverter` (executable, resources `.process("Resources")`), two test targets; `defaultLocalization: "en"`
- `Resources/Info.plist` - bundle id `com.hypervideo.converter`, video category, document types (Video viewer, Folder)
- Localizations: en and pt-BR (`Localizable.strings`)

## Platform Requirements

**Development:**
- macOS 26+, Swift 6.2+ toolchain (Command Line Tools suffice; full Xcode only for notarization)

**Production:**
- Distributed as signed `.app` inside a `.dmg` from `dist/`; macOS 26+

---

*Stack analysis: 2026-10-19*
