<!-- refreshed: 2026-10-19 -->
# Architecture

**Analysis Date:** 2026-10-19

## System Overview

```text
┌─────────────────────────────────────────────────────────────┐
│              SwiftUI App (target HyperVideoConverter)        │
├──────────────────┬──────────────────┬───────────────────────┤
│  App / Commands  │  Views (pages,   │  Stores (@Observable  │
│  `App/`          │  workspace,      │  @MainActor models)   │
│                  │  inspector)      │  `Stores/`            │
│                  │  `Views/`        │                       │
└────────┬─────────┴────────┬─────────┴──────────┬────────────┘
         ▼                  ▼                     ▼
┌─────────────────────────────────────────────────────────────┐
│           HyperVideoCore library (no UI)                     │
│  Models/ (Sendable value types)  Engine/ (AVFoundation)      │
│  `Sources/HyperVideoCore`                                    │
└─────────────────────────────────────────────────────────────┘
         ▼
┌─────────────────────────────────────────────────────────────┐
│ AVAssetReader/Writer + VideoToolbox, custom Matroska writer, │
│ JSON files (queue.json, presets) + UserDefaults              │
└─────────────────────────────────────────────────────────────┘
```

## Component Responsibilities

| Component | Responsibility | File |
|-----------|----------------|------|
| App entry | Scenes (WindowGroup + Settings), AppDelegate, menu commands | `Sources/HyperVideoConverter/App/HyperVideoConverterApp.swift` |
| QuitCoordinator | Confirms/handles quit while jobs run, sweeps temp files | `Sources/HyperVideoConverter/App/QuitCoordinator.swift` |
| AppModel | Root observable state: sources, selection, section, mode, drafts | `Sources/HyperVideoConverter/Stores/AppModel.swift` (+ `+Import`, `+Mode`, `+Workspace` extensions) |
| QueueStore | Job queue, running Tasks, progress, history, persistence | `Sources/HyperVideoConverter/Stores/QueueStore.swift` |
| PresetStore | User/built-in presets, favorites | `Sources/HyperVideoConverter/Stores/PresetStore.swift` |
| Persistence | `JSONStore<T>` file load/save; `CoalescingSaver` debounced writes | `Stores/Persistence.swift`, `Stores/CoalescingSaver.swift` |
| Notifier | `QueueNotifying` protocol + `SystemNotifier` | `Stores/Notifier.swift` |
| TranscodeEngine | Encode source to destination, returns size; stall detection | `Sources/HyperVideoCore/Engine/TranscodeEngine.swift` |
| PipelineFactory / SamplePump | Builds per-track reader/writer pumps | `Engine/PipelineFactory.swift`, `Engine/SamplePump.swift` |
| OutputSettingsBuilder / GeometryPlanner | AV output dictionaries, sizing/crop | `Engine/OutputSettingsBuilder.swift`, `Engine/GeometryPlanner.swift` |
| Filters / burn-in | Core Image filters, subtitle burn-in | `Engine/FrameFilter.swift`, `Engine/FilterCompositor.swift`, `Engine/SubtitleBurner.swift` |
| Matroska | EBML writer and MOV→MKV remux | `Engine/Matroska/*.swift` |
| Inspection | MediaInfo, discovery, security-scoped bookmarks | `Engine/MediaInspector.swift`, `Engine/MediaDiscovery.swift`, `Engine/FileBookmarks.swift` |

## Pattern Overview

**Overall:** Two-module layering — a UI-free core library + SwiftUI app using Observation-based stores (MVVM-ish, single root model).

**Key Characteristics:**
- Core types are `public`, `Sendable` value types (`EncodeSettings`, `EncodeJob`, `Preset`, `MediaInfo`).
- App stores are `@Observable @MainActor final class`; non-UI fields marked `@ObservationIgnored`.
- Async/await with Swift 6.2 strict concurrency; `@preconcurrency import AVFoundation`.
- Dependency injection via init params (`directory`, `defaults`, `notifier`, `saveDelay`) for tests.

## Layers

**Core Models:**
- Purpose: Settings, presets, jobs, estimates, subtitles
- Location: `Sources/HyperVideoCore/Models/`
- Depends on: Foundation/CoreMedia only
- Used by: Engine, app

**Core Engine:**
- Purpose: Media inspection and transcoding
- Location: `Sources/HyperVideoCore/Engine/`
- Depends on: Models, AVFoundation, VideoToolbox, Core Image
- Used by: `QueueStore`, `AppModel+Import`

**App Stores:**
- Purpose: State, queue orchestration, persistence
- Location: `Sources/HyperVideoConverter/Stores/`
- Depends on: HyperVideoCore
- Used by: Views

**Views:**
- Purpose: SwiftUI UI
- Location: `Sources/HyperVideoConverter/Views/`
- Depends on: Stores (via `AppModel` in environment)

## Data Flow

### Primary Conversion Path

1. Drop/open files → `AppModel+Import.swift` (folders → `FolderImport` sheet, `MediaDiscovery`)
2. `MediaInspector` loads `MediaInfo`; `SourceItem` gets `EncodeSettings` from preset
3. Inspector views edit settings of selected sources (`Views/Inspector/`)
4. Enqueue → `QueueStore` creates `EncodeJob`s, persists via `CoalescingSaver` to `queue.json`
5. `QueueStore` runs `TranscodeEngine.run(source:destination:settings:subtitleFiles:progress:)` in a `Task`; progress goes into `JobProgress` boxes
6. Engine: validate → `AVAssetReader`/`AVAssetWriter` in hidden `.hypervideo-<UUID>` work dir → pumps → MKV remux if needed (`MatroskaRemuxer`) → move to destination
7. Completion → history, `Notifier`

**State Management:**
- `AppModel` owns `PresetStore`, `QueueStore`, `UIState`; injected into views.
- Persisted: JSON files (queue, presets) + `UserDefaults` preferences; file access via bookmarks.

## Key Abstractions

**EncodeSettings:** full encode description, with `isValid`/`validationIssues` — `Models/EncodeSettings.swift`
**EncodeJob:** queued unit with state machine, relaunch restoration — `Models/Job.swift`
**SamplePump:** per-track copy loop — `Engine/SamplePump.swift`
**JSONStore / CoalescingSaver:** generic persistence — `Stores/Persistence.swift`

## Entry Points

**App:** `Sources/HyperVideoConverter/App/HyperVideoConverterApp.swift` (`@main`)
**Packaging:** `Scripts/build-app.sh` (builds .app + .dmg into `dist/`, optional signing/notarization)

## Architectural Constraints

- **Threading:** UI and stores on MainActor; encoding in async Tasks; engine is a `Sendable` struct.
- **Global state:** `UserDefaults.standard` defaults; no singletons beyond that.
- **Platform:** macOS 26 minimum (`Package.swift`), Swift tools 6.2.
- **Localization:** default `en`, `pt-BR.lproj` in `Sources/HyperVideoConverter/Resources/`.

## Anti-Patterns

### Putting AVFoundation logic in the app target
**What happens:** Engine-level code in Stores/Views.
**Why it's wrong:** Breaks testability in `HyperVideoCoreTests`.
**Do this instead:** Add to `Sources/HyperVideoCore/Engine/` and expose `public` API.

### Observing high-frequency progress
**What happens:** Writing progress into `jobs` triggers full list redraws.
**Do this instead:** Use `JobProgress` boxes (`Stores/JobProgress.swift`).

## Error Handling

**Strategy:** Typed `LocalizedError` enums (`TranscodeError`, `MediaInspectorError`) with user-facing messages; job state stores failure text.

**Patterns:**
- Validate settings before work; stall timeout converts deadlocks to `.stalled`.
- `defer` cleanup of temp work dir.

## Cross-Cutting Concerns

**Logging:** Not detected (no logging framework).
**Validation:** `EncodeSettings.validationIssues`.
**Authentication:** Not applicable; sandbox file access via `FileBookmarks`.

---

*Architecture analysis: 2026-10-19*
