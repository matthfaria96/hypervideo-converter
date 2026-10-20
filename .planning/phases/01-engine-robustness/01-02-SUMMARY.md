---
phase: 01-engine-robustness
plan: 02
subsystem: engine/pump
tags: [stall, gcd, cancellation]
requires: []
provides: [ENG-03]
key-files:
  created: [Tests/HyperVideoCoreTests/SamplePumpStallTests.swift]
  modified: [Sources/HyperVideoCore/Engine/SamplePump.swift]
decisions:
  - "whenIdle runs the cancel work on timeout as well, guarded run-once by a Mutex; the notify path always releases parked blocks"
  - "The 5 ms polling loop is replaced by a OneShot continuation (Sendable, Mutex-backed) resumed by notify or by a detached timeout task"
metrics:
  completed: 2026-10-20
---

# Phase 1 Plan 02: Stall cancellation without leaked threads Summary

SamplePump.whenIdle now runs the reader/writer cancel work exactly once, either when every pump queue is parked or when the timeout fires. Once a stuck AVFoundation call is unblocked, its queue parks, gets released and drains, so no GCD thread stays blocked.

## Tasks
| Task | Commit | Notes |
|------|--------|-------|
| 1 RED | 0e7f87d | Adds the internal `init(next:input:label:)`, `drained(timeout:)` and the `OneShot` helper. Before the fix, test A (work never ran) and test B (queue never drained) failed. Test C passed. |
| 2 GREEN | 1f3e1de | whenIdle rewritten. `swift test --filter "SamplePump\|Stress\|TranscodeIntegration"` passed 30/30. |

## Deviations from Plan
- Added a small `OneShot` class in SamplePump.swift, shared by `drained` and `whenIdle`, for the "resume exactly once" continuation. It is a Sendable class backed by a Mutex, with no new @unchecked.
- The test counter is a Sendable class around a Mutex, because a tuple can't hold a noncopyable Mutex.

## Self-Check: PASSED
