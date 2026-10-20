---
phase: 02-queue-responsiveness
plan: 02
subsystem: ui
tags: [concurrency, appkit, presets, panels]
requires: []
provides: [async PresetStore.importPresets, PresetStore.parseImport, PanelPresenter]
affects: [FavoritesView, AppModel]
tech-stack:
  added: []
  patterns: [Task.detached for file IO + parse, sheet-modal panels via PanelPresenter]
key-files:
  created:
    - Sources/HyperVideoConverter/Stores/PanelPresenter.swift
    - Tests/HyperVideoConverterTests/PresetImportTests.swift
  modified:
    - Sources/HyperVideoConverter/Stores/PresetStore.swift
    - Sources/HyperVideoConverter/Stores/AppModel.swift
    - Sources/HyperVideoConverter/Views/Pages/FavoritesView.swift
decisions:
  - "parseImport is a nonisolated static pure function; Preset is already Sendable so no wrapper needed"
  - "Panel completions hop with MainActor.assumeIsolated (AppKit calls them on main)"
requirements: [UI-01, UI-02]
metrics:
  completed: 2026-10-20
  tasks: 2
---

# Phase 02 Plan 02: Async Preset Import and Sheet Panels Summary

Preset import now reads and parses the file in a detached task (`PresetStore.parseImport`) and appends on main; all four `runModal` call sites go through `PanelPresenter`, which attaches panels as sheets to the key/main window and falls back to `begin()`.

## Commits
- ee953c6 test(02-02): add failing tests for async preset import
- f7e18e0 feat(02-02): read and parse preset imports off the main actor
- e1f0519 feat(02-02): present open and save panels as window sheets

## Verification
- `grep -rn runModal Sources` is empty
- Full `swift test`: 160 tests / 30 suites and 112 tests / 22 suites, all passing (4 new in PresetImportTests)

## Deviations from Plan
- [Rule 3 - Blocking] Making `importPresets` async broke the FavoritesView call site in Task 1, so the call site was wrapped in `Task { await ... }` in the Task 1 commit (import/alert message split into small helpers; localization strings unchanged). Task 2 then moved it onto PanelPresenter.

## Threat Flags
None. T-02-03: decode failure throws before `custom` is touched (tested); user sees the same generic message.

## Known Stubs
None.

## Self-Check: PASSED
