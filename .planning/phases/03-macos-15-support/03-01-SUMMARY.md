---
phase: 03-macos-15-support
plan: 01
subsystem: engine
tags: [macos15, avfoundation, compat]
requires: []
provides: [macOS 15 deployment target, pre-26 video composition path]
affects: [03-02]
key-files:
  modified: [Package.swift, Resources/Info.plist, Sources/HyperVideoCore/Engine/PipelineFactory.swift]
decisions:
  - "Single pre-26 path (AVMutableVideoComposition) instead of #available split; not deprecated-to-error under Swift 6"
requirements: [CMP-01]
completed: 2026-10-20
---

# Phase 3 Plan 01: macOS 15 deployment target (engine) Summary

Deployment target lowered to macOS 15; HyperVideoCore builds with a single AVMutableVideoComposition path producing the same settings as the macOS 26 Configuration API.

## Error list after platform change (Task 1)
- PipelineFactory.swift:164 `AVVideoCompositionLayerInstruction.Configuration` (26.0+)
- PipelineFactory.swift:166, :167, :171 `init(configuration:)` (26.0+)
- MediaInspector.swift / OutputSettingsBuilder.swift / SamplePump.swift: no own errors (failed only as part of the same compile batch)
- App target: ContentView.swift:80, :89 `sharedBackgroundVisibility` (26.0+) — left for 03-02

## Chosen path per file
- PipelineFactory.swift: AVMutableVideoCompositionLayerInstruction + AVMutableVideoCompositionInstruction + AVMutableVideoComposition, returned as an immutable `copy()`. Colour primaries/transfer/matrix, compositor class, frame duration formula and render size unchanged.
- MediaInspector.swift, OutputSettingsBuilder.swift: no change needed.

## Verification
- `swift build --target HyperVideoCore`: clean, no availability warnings.
- HyperVideoCoreTests: 160 tests in 30 suites passed (run via `xcrun xctest` on the built bundle, since `swift test` also builds the app target, which fails until 03-02).
- HyperVideoConverterTests not run (depends on app target; 03-02).

## Commits
- 56e5d14 chore(03-01): lower deployment target to macOS 15
- 0273ec5 feat(03-01): pre-26 AVFoundation video composition path

## Deviations from Plan
- Core tests run through `xcrun xctest` instead of `swift test --filter` (app target blocks the latter). The `sharedBackgroundVisibility` fix is not trivial (needs a ToolbarContent compat helper, D-03), so it stays with 03-02.

## Self-Check: PASSED
