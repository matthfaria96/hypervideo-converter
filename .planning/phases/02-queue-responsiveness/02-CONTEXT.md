# Phase 2: Queue & responsiveness - Context

**Gathered:** 2026-10-20 (auto, discuss skipped)

## Phase Boundary
Requirements QUE-01, QUE-02, QUE-03, UI-01, UI-02 (see .planning/REQUIREMENTS.md, details in .planning/codebase/CONCERNS.md).

## Decisions
- D-01: Removing a running job cancels its encode AND removes it from the list (no lingering row).
- D-02: Work folders embed the job id in the folder name; the startup/periodic sweep skips folders whose id belongs to a running job of this process.
- D-03: Dock progress refresh is throttled (time- or delta-based), final state always applied.
- D-04: queue.json load, preset import file read and retry fileExists checks run off the main actor (Task.detached / nonisolated async helpers), results applied on main.
- D-05: NSOpenPanel uses beginSheetModal(for:) on the key window (fallback begin() when no window), never runModal.
- D-06: Tests first (Swift Testing). Package.swift platform untouched. Build with DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer.

## Claude's Discretion
Throttle interval, helper names, file layout.

## Deferred
macOS 15 support (Phase 3).
