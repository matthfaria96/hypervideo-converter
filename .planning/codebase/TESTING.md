# Testing Patterns

**Analysis Date:** 2026-10-19

## Current Results (2026-10-19)

- `swift build`: **Build complete** (~6 s). Only linker warnings about missing CommandLineTools search paths (`/Library/Developer/CommandLineTools/Developer/usr/lib`), harmless.
- `swift test`: **all passing, 0 failures**
  - `HyperVideoCoreTests`: 143 tests in 25 suites passed (~9.4 s)
  - `HyperVideoConverterTests`: 99 tests in 19 suites passed (~4.8 s)
  - Total: 242 tests, 44 suites

## Test Framework

**Runner:**
- Swift Testing (`import Testing`), Swift tools 6.2, macOS 26. No XCTest.
- Config: `Package.swift` (test targets `HyperVideoCoreTests`, `HyperVideoConverterTests`)

**Assertion Library:**
- `#expect(...)`, `try #require(...)`

**Run Commands:**
```bash
swift test                                   # Run all tests
swift test --filter QueueStoreTests          # One suite
swift test --enable-code-coverage            # Coverage
```

## Test File Organization

**Location:** Separate `Tests/` tree, one folder per target.

**Naming:** `<Feature>Tests.swift`; helpers without suffix.

**Structure:**
```
Tests/
├── HyperVideoCoreTests/       # engine, models, Matroska, transcodes
│   ├── StressClip.swift       # generates synthetic source videos
│   └── MatroskaReader.swift   # parses MKV output for assertions
└── HyperVideoConverterTests/  # stores, queue, persistence, UX logic, localization
    ├── TestEnvironment.swift  # isolated temp dir + UserDefaults suite
    └── AppTestClip.swift      # synthetic clips for app tests
```

## Test Structure

**Suite Organization:**
```swift
@MainActor
@Suite("Queue destinations")
struct QueueStoreTests {
    @Test func cancelledAndFailedJobsKeepTheirDestinationReserved() throws {
        let env = try TestEnvironment()
        let queue = env.makeQueue()
        let first = job(env)
        queue.add([first])
        queue.cancel(first.id)
        #expect(queue.jobs.first?.state == .cancelled)
        #expect(queue.takenDestinations.contains(first.destination))
    }
}
```

**Patterns:**
- Suites are `struct`s with a human-readable `@Suite("...")` name; test names are behavior sentences in camelCase.
- App tests are `@MainActor`. Heavy encode suites use `.serialized` (`StressTranscodeTests`).
- Setup: build a fresh `TestEnvironment()` per test (unique temp folder and `UserDefaults(suiteName:)`). No shared state.
- Teardown: none explicit; temp directories under `FileManager.default.temporaryDirectory`.

## Mocking

**Framework:** None; dependency injection via init parameters.

**Patterns:**
```swift
QueueStore(directory: support, defaults: defaults, saveDelay: 0, resolvesInBackground: false)
```
- Notifications injected through the `QueueNotifying` protocol (`NotificationTests.swift`).

**What to Mock:** Persistence directory, `UserDefaults`, notifier, timings (`saveDelay: 0`, `stallTimeout`).

**What NOT to Mock:** AVFoundation encoding — tests run real transcodes on tiny generated clips.

## Fixtures and Factories

**Test Data:**
```swift
let clip = try await AppTestClip.make(in: env.root, .init(name: "clip"))
let source = try await StressClip.make(in: dir, Spec(codec: .proRes422))
```
- `StressClip.Spec` covers odd sizes, rotation, VFR, 10-bit HEVC, ProRes, audio layouts, metadata. No binary fixtures committed.

**Location:** `Tests/HyperVideoCoreTests/StressClip.swift`, `Tests/HyperVideoConverterTests/AppTestClip.swift`.

## Coverage

**Requirements:** None enforced.

**View Coverage:**
```bash
swift test --enable-code-coverage && swift test --show-codecov-path
```

## Test Types

**Unit Tests:** Models/logic (`EstimateTests`, `FilterTests`, `SizePredictionTests`, `HandBrakePresetTests`, `UXLogicTests`, `SettingsMerging` via `PresetTrimCropTests`).

**Integration Tests:** Real encodes and file I/O (`TranscodeIntegrationTests`, `MatroskaTranscodeTests`, `StressTranscodeTests`, `QueuePersistenceTests`, `QuitAndSweepTests`).

**E2E Tests:** Not used (no UI automation for SwiftUI views).

## Common Patterns

**Async Testing:**
```swift
await model.addSources([clip])
#expect(try await TestEnvironment.waitUntil { model.sources.first?.info != nil })
```
Use `TestEnvironment.waitUntil` polling instead of sleeps.

**Error Testing:**
```swift
#expect(throws: MatroskaTrack.UnsupportedFormat.self) { try ... }
```
Errors are `Equatable` enums so specific cases can be asserted.

---

*Testing analysis: 2026-10-19*
