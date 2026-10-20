---
phase: 01-engine-robustness
plan: 04
subsystem: app/queue
tags: [localization, queue, disk-space]
requires: [01-02, 01-03]
provides: [ENG-02-app, ENG-04-app]
key-files:
  created: [Sources/HyperVideoConverter/Stores/JobErrorMessage.swift, Tests/HyperVideoConverterTests/JobErrorMessageTests.swift]
  modified: [Sources/HyperVideoConverter/Stores/QueueStore.swift, Sources/HyperVideoConverter/Resources/pt-BR.lproj/Localizable.strings, Tests/HyperVideoConverterTests/LocalizationTests.swift]
decisions:
  - "JobErrorMessage localizes insufficientSpace via String(localized:) with %@ sizes; other errors keep localizedDescription"
  - "QueueStore uses engine.transcode and stores TranscodeOutput.url as the job destination when it differs"
metrics:
  completed: 2026-10-20
---

# Phase 1 Plan 04: App wiring for disk-space and renamed outputs Summary

Failed jobs now show a translated insufficient-space message (EN + pt-BR). When the engine renamed the output at move time, the completed job and its notification point at the file that was really written.

## Tasks
| Task | Commit | Notes |
|------|--------|-------|
| 1 RED | c8dfc73 | The build failed on the missing JobErrorMessage. |
| 1 GREEN | 96047ee | Helper plus the pt-BR string; `plutil -lint` OK. |
| 2 | 4e82b5c | QueueStore wired; a private `EncodeJob.with(destination:)` extension lives in QueueStore.swift. |

## Verification
- `swift build`: Build complete.
- `swift test`: HyperVideoCoreTests 155/155 and HyperVideoConverterTests 102/102 passed, 257/257 in total.
- Package.swift is unchanged.

## Deviations from Plan
- The "job finished" notification also receives the job with its updated destination.
- Environment: run with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. The selected Command Line Tools toolchain can't load the SwiftUI macro plugin, which fails before any of this code is compiled.

## Self-Check: PASSED
