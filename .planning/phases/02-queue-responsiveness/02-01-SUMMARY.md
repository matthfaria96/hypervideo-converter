---
phase: 02-queue-responsiveness
plan: 01
subsystem: queue
tags: [queue, work-folders, cancellation, tdd]
requires: []
provides: [WorkFolder, TranscodeEngine.transcode(workTag:), QueueStore pendingRemoval, scoped sweep]
affects: [QueueStore, TranscodeEngine]
key-files:
  created:
    - Sources/HyperVideoCore/Engine/WorkFolder.swift
    - Tests/HyperVideoCoreTests/WorkFolderTests.swift
    - Tests/HyperVideoConverterTests/QueueRemoveRunningTests.swift
  modified:
    - Sources/HyperVideoCore/Engine/TranscodeEngine.swift
    - Sources/HyperVideoConverter/Stores/QueueStore.swift
    - Tests/HyperVideoConverterTests/QuitAndSweepTests.swift
decisions:
  - Work folders named .hypervideo-<jobID>-<uuid>; legacy .hypervideo-<uuid> still recognised and swept at launch
  - Removed running jobs stay visible as running until their task ends, then leave the list (no .cancelled row)
requirements: [QUE-01, QUE-02]
completed: 2026-10-20
---

# Phase 2 Plan 01: Remove running jobs + scoped work-folder sweep Summary

Removing a running job now cancels it and drops the row once the encode stops (also across quit/relaunch); work folders carry the job id so the sweep never touches a running job's folder and stopImmediately only deletes folders of the jobs it interrupted.

## Tasks
| Task | Commits |
|------|---------|
| 1. WorkFolder + engine workTag | e486459 (test), 511e7d1 (feat) |
| 2. QueueStore pendingRemoval + scoped sweep | see git log: test(02-01) + fix(02-01) commits |

## Details
- `WorkFolder` (Core): `name(jobID:)`, `jobID(fromName:)`, `isWorkFolder(name:)`.
- `TranscodeEngine.transcode(..., workTag: UUID? = nil, ...)`.
- `QueueStore`: `pendingRemoval`; `finish` split into `finish` + `record` (keeps functions short); `settleInterrupted` shared by `stopForQuit`/`stopImmediately`; `sweepStaleWorkDirectories(in:skipping:onlyOwnedBy:)`.

## Verification
Full `swift test`: 160 tests / 30 suites (XCTest-hosted run) and 108 tests / 21 suites passed, 0 failures.

## Deviations from Plan
None - plan executed as written (finish was split into a helper to keep functions under 50 lines).

## Threat mitigations
T-02-01: sweep deletes only names passing `WorkFolder.isWorkFolder`, skips running ids, stopImmediately limited to owned ids.

## Self-Check: PASSED
