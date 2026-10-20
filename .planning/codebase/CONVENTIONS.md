# Coding Conventions

**Analysis Date:** 2026-10-19

## Naming Patterns

**Files:**
- One primary type per file, named after the type: `Sources/HyperVideoConverter/Stores/QueueStore.swift`, `Sources/HyperVideoCore/Engine/TranscodeEngine.swift`.
- Extensions split by concern use `Type+Concern.swift`: `AppModel+Import.swift`, `AppModel+Mode.swift`, `AppModel+Workspace.swift`.
- SwiftUI views end in `View`, `Tab`, `Sheet`, `Card`, `Chip` (`SidebarView.swift`, `TrimTab.swift`, `FolderImportSheet.swift`, `EstimateCard.swift`, `ScopeChip.swift`).
- Tests end in `Tests.swift`; test helpers have plain names (`StressClip.swift`, `AppTestClip.swift`, `TestEnvironment.swift`, `MatroskaReader.swift`).

**Functions:**
- lowerCamelCase, verb-first, read like sentences: `addSources(_:)`, `enqueue(_:)`, `makePumps()`, `restoredAfterRelaunch()`, `droppingBookmarksWhenCompleted()`.
- Non-mutating transforms use past-participle / `-ing` names returning copies (`droppingBookmarksWhenCompleted()`, `pruned(_:)`).
- Factories use `make…` (`makeQueue()`, `makeModel()`, `StressClip.make(in:_:)`).

**Variables:**
- lowerCamelCase; booleans as `is…`/`has…`/verb phrases (`isProcessing`, `isReady`, `resolvesInBackground`).
- Static constants on the type: `static let historyLimit = 200`.

**Types:**
- UpperCamelCase. Errors are enums conforming to `Error`/`LocalizedError` (`TranscodeError` in `Sources/HyperVideoCore/Engine/TranscodeEngine.swift`, `MatroskaTrack.UnsupportedFormat`).
- Protocols for injectable dependencies end in `-ing` (`QueueNotifying` in `Sources/HyperVideoConverter/Stores/Notifier.swift`).

## Code Style

**Formatting:**
- No SwiftLint/SwiftFormat config in the repo. Follow existing style: 4-space indent, long-ish lines (~120 chars), trailing closures, Swift 5.9+ `switch`/`if` expressions (e.g. `errorDescription` in `TranscodeEngine.swift`).

**Linting:**
- None configured. Swift 6.2 tools (`Package.swift`) with strict concurrency is the de-facto lint: keep builds warning-free.

## Concurrency

- UI/state classes are `@Observable @MainActor final class` (`QueueStore`, `AppModel`).
- Mark non-observed internals `@ObservationIgnored` (tasks, savers, engines) to avoid redraws.
- Core engine types are `Sendable` structs (`TranscodeEngine`). AVFoundation imported with `@preconcurrency import AVFoundation`.
- Use `async throws` for AVFoundation pipelines (`PipelineFactory.swift`).

## Import Organization

**Order:**
1. Foundation / Apple frameworks (`Foundation`, `AVFoundation`, `VideoToolbox`, `Observation`, `SwiftUI`)
2. `HyperVideoCore`
3. `@testable import` (tests only)

**Path Aliases:** Not applicable (SwiftPM modules: `HyperVideoCore`, `HyperVideoConverter`).

## Module Boundaries

- `Sources/HyperVideoCore` — pure engine/models, `public` API, no SwiftUI.
- `Sources/HyperVideoConverter` — app: `App/`, `Stores/`, `Views/` (subfolders `Inspector/`, `Workspace/`, `Components/`, `Pages/`).
- Keep logic testable in Core or in Stores; Views stay thin.

## Error Handling

- Throw typed enum errors with user-facing `errorDescription` strings (`TranscodeError`).
- Jobs capture failures into state (`EncodeJob.state`, `.completed(outputBytes:elapsed:)`, failed/cancelled) rather than crashing.
- Persistence loads fail soft: `store.load() ?? []` in `QueueStore.init`.

## Logging

**Framework:** `os.Logger` — single `appLog` in `Sources/HyperVideoConverter/Stores/Persistence.swift` (subsystem `com.hypervideo.converter`).

**Patterns:** Use `appLog` for diagnostics; no `print(` in Sources.

## Localization

- English base (`defaultLocalization: "en"`), Portuguese in `Sources/HyperVideoConverter/Resources/pt-BR.lproj`.
- Use `String(localized:)` for non-view strings (`PresetStore.swift`); SwiftUI literals are localized automatically. `Tests/HyperVideoConverterTests/LocalizationTests.swift` checks coverage — add pt-BR entries for new strings.

## Comments

- `///` doc comments on non-obvious properties and inits explaining *why* (see `QueueStore` init doc, `TranscodeEngine.stallTimeout`).
- Inline `//` only for intent in tests or tricky flow.

## Function Design

**Size:** Files mostly 30-300 lines; largest `QueueStore.swift` (370), `MatroskaRemuxer.swift` (307). Keep files under ~400 lines and split via extensions.

**Parameters:** Dependency injection through init defaults for tests (`directory: URL? = nil, defaults: UserDefaults = .standard, notifier:, saveDelay:, resolvesInBackground:`).

**Return Values:** Prefer value types and returning copies; `private(set)` for state exposed read-only.

## Module Design

**Exports:** `public` only in `HyperVideoCore`; app module internal, accessed in tests via `@testable import`.

**Barrel Files:** Not used.

---

*Convention analysis: 2026-10-19*
