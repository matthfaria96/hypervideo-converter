# Phase 1: Engine robustness - Context

**Gathered:** 2026-10-19 (autonomous, discuss skipped)

## Phase Boundary
Encodes never crash or fail late for avoidable reasons. Requirements ENG-01..ENG-04.

## Decisions (Claude's discretion, autonomous)
- ENG-01: MatroskaRemuxer must handle zero-byte samples without crashing (skip or write empty block safely) — regression test first.
- ENG-02: TranscodeEngine resolves a unique destination name at the moment of the final move (not only at start); test creates the destination mid-encode.
- ENG-03: SamplePump stall detection cancels AVAssetReader/Writer and completes without leaking threads; test with an injected stalled source.
- ENG-04: Free disk-space pre-check before encoding (estimate ~2x source for MKV, ~1x otherwise, via URLResourceValues volumeAvailableCapacityForImportantUsage); failure message translated in EN + pt-BR in the existing localization catalog.
- Tests first (Swift Testing). `swift build` and `swift test` fully green at end.
- Do NOT change Package.swift platform (phase 3).

## Canonical refs
- .planning/ROADMAP.md, .planning/REQUIREMENTS.md, .planning/codebase/CONCERNS.md
