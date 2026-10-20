---
phase: 01-engine-robustness
plan: 01
subsystem: engine/matroska
tags: [matroska, crash, regression-test]
requires: []
provides: [ENG-01]
key-files:
  created: [Tests/HyperVideoCoreTests/MatroskaEmptySampleTests.swift]
  modified: [Sources/HyperVideoCore/Engine/Matroska/MatroskaRemuxer.swift]
decisions:
  - "Zero-byte samples become empty packets that keep their timing; the copy path only runs when size > 0"
metrics:
  completed: 2026-10-20
---

# Phase 1 Plan 01: Zero-byte Matroska samples Summary

MatroskaRemuxer.packets(in:track:isText:) now emits an empty, correctly timed packet for zero-byte samples instead of force-unwrapping a nil baseAddress or dropping the sample.

## Tasks
| Task | Commit | Notes |
|------|--------|-------|
| 1 RED test | 39621ec | `packets` and `Packet` made internal for @testable access. Before the fix, the empty sample was dropped (counts 2 and 0 instead of 3 and 1). |
| 2 GREEN fix | 1f94ae7 | `size > 0` guards the copy; `baseAddress` is guarded and returns kCMBlockBufferBadPointerParameterErr. |

Verification: `swift test --filter Matroska` passed 26/26.

## Deviations from Plan
- Environment: the Command Line Tools toolchain cannot load the SwiftUI macro plugin, so all builds and tests run with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. No code change.
- RED showed up as dropped packets, not a crash: CMBlockBufferCopyDataBytes rejected the empty copy before the force-unwrap could trap in this configuration. Either way the bug was real.

## Self-Check: PASSED
