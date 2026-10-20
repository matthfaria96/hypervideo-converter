---
phase: 01-engine-robustness
plan: 03
subsystem: engine/transcode
tags: [naming, disk-space]
requires: []
provides: [ENG-02, ENG-04-engine]
key-files:
  created: [Sources/HyperVideoCore/Engine/DiskSpace.swift, Tests/HyperVideoCoreTests/FinalMoveTests.swift, Tests/HyperVideoCoreTests/DiskSpaceTests.swift]
  modified: [Sources/HyperVideoCore/Engine/TranscodeEngine.swift]
decisions:
  - "TranscodeEngine.transcode returns TranscodeOutput(url, bytes); run is a thin wrapper returning bytes"
  - "Unique name re-resolved via OutputNaming right before moveItem, retried up to 4 attempts on fileWriteFileExists; never overwrites"
  - "Space precheck needs 2x the source for MKV and 1x otherwise, runs before the work folder is created, and is skipped when capacity or source size is unknown"
metrics:
  completed: 2026-10-20
---

# Phase 1 Plan 03: Final-move naming and disk-space precheck Summary

The engine now picks a unique output name at the moment of the final move ("out 2.mp4" if "out.mp4" appeared mid-encode, leaving the other file untouched) and returns the real URL. It also throws `TranscodeError.insufficientSpace(required:available:)` before creating any work folder when the destination volume is short on space. Capacity is injectable through `TranscodeEngine(availableCapacity:)`.

## Tasks
| Task | Commit | Notes |
|------|--------|-------|
| 1 RED | a314b2c | Build failed on the missing `transcode`, `DiskSpace` and `insufficientSpace`. |
| 2 GREEN | 481694d | `swift test --filter "FinalMove\|DiskSpace\|TranscodeIntegration\|Matroska\|Stress"` passed 58/58. |

## Deviations from Plan
- [Rule 1 - test bug] AVFoundation can't open MKV output, so the MKV collision test checks the EBML magic bytes instead of calling MediaInspector.inspect.
- Added the `availableCapacityReadsTheVolume` test and an overflow assertion for requiredBytes.

## Self-Check: PASSED
