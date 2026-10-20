---
phase: 02-queue-responsiveness
plan: 03
subsystem: queue
tags: [dock, throttle, background-io, main-actor]
requires: [02-01, 02-02]
provides: [DockThrottle, background queue.json load, async retry]
affects: [QueueStore, HistoryView (unchanged call sites)]
tech-stack:
  added: []
  patterns: [immutable value-type throttle, Task.detached for disk I/O]
key-files:
  created:
    - Sources/HyperVideoConverter/Stores/DockThrottle.swift
    - Tests/HyperVideoConverterTests/DockThrottleTests.swift
    - Tests/HyperVideoConverterTests/QueueBackgroundIOTests.swift
  modified:
    - Sources/HyperVideoConverter/Stores/QueueStore.swift
    - Tests/HyperVideoConverterTests/QueueStoreTests.swift
    - Tests/HyperVideoConverterTests/WorkspaceTests.swift
decisions:
  - "persist() and flushPersistence() are no-ops while !isReady; finishLaunch saves the merged list once"
  - "retry returns @discardableResult Task<Void, Never>; fileExists runs in Task.detached"
  - "QueueStore.pruned/historyLimit made nonisolated so the detached load can prune"
metrics:
  completed: 2026-10-20
  tasks: 2
---

# Phase 2 Plan 3: Dock Throttle and Background Queue I/O Summary

Dock refreshes are throttled to one per 0.5 s on progress ticks (forced on every state change), queue.json is read/restored/resolved/swept in a detached task with saved jobs merged ahead of jobs added meanwhile, and retry's fileExists check runs off the main actor.

## Commits
- bdfed53 test(02-03): add failing tests for dock throttle
- 90e4f5c feat(02-03): throttle dock refresh during progress ticks
- 0bc59ba test(02-03): add failing tests for background queue load and async retry
- 56c212d feat(02-03): load queue.json and check retry destinations off the main actor

## Verification
`swift build` clean; `swift test` green: 160 tests / 30 suites (Swift Testing) and 123 tests / 24 suites (second run), 0 failures. Package.swift unchanged. `fileExists` in QueueStore only inside Task.detached.

## Deviations from Plan
**1. [Rule 3 - Blocking] `pruned` and `historyLimit` marked `nonisolated`** so the detached launch task can call them (compile error otherwise). Pure functions, no behavior change.

Otherwise plan executed as written. The sweep in finishLaunch passes `skipping: []` since no job can run before `isReady`.

## TDD Gate Compliance
RED commits bdfed53, 0bc59ba precede GREEN commits 90e4f5c, 56c212d.

## Threat Model
T-02-05 mitigated: corrupt file still decodes to []; nothing is written before the load completes.

## Self-Check: PASSED
