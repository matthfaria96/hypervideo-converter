# Phase 3: macOS 15 support - Context

**Gathered:** 2026-10-20 (auto, discuss skipped)

## Phase Boundary
Requirements CMP-01, CMP-02, CMP-03 (.planning/REQUIREMENTS.md).

## Findings (pre-planning probe)
- Switching Package.swift to `.macOS(.v15)` fails to compile only in HyperVideoCore/Engine:
  PipelineFactory.swift (~L164-171: `AVVideoCompositionLayerInstruction.Configuration`,
  `AVVideoCompositionInstruction(configuration:)`, `AVVideoComposition(configuration:)`),
  MediaInspector.swift and OutputSettingsBuilder.swift (same class of macOS 26 AVFoundation API).
  Full error list: run `swift build` after the platform change.
- UI: ContentView.swift uses `.sharedBackgroundVisibility(.hidden)` on ToolbarItems (macOS 26).
  Theme.swift has no glassEffect today (custom ButtonStyles) — still audit all Views for 26+ APIs.
- Reference: Sirena/App/Compat/GlassCompat.swift (`supportsLiquidGlass`, `compatGlass`,
  `compatGlassButtonStyle`, `compatGlassProminentButtonStyle`) with `if #available(macOS 26, *)`.

## Decisions
- D-01: Package.swift `.macOS(.v15)`, keep swift-tools-version 6.2 if it builds.
- D-02: Engine: `if #available(macOS 26, *)` keeps the new Configuration API; else branch uses the
  pre-26 mutable API (AVMutableVideoComposition etc.) producing identical settings. Prefer a single
  pre-26 path if it is not deprecated-to-error. Existing engine tests must stay green.
- D-03: UI compat helpers in Sources/HyperVideoConverter/Views/Components/Compat.swift (mirror Sirena);
  toolbar `sharedBackgroundVisibility` wrapped in a ToolbarContent/ ToolbarItem compat helper.
- D-04: After build, `nm -u` / `nm -m` on built .o files and binary for macOS 26/27-only weak type
  descriptors (TupleContentVMn, GlassVMn, ...). Any outside availability guards must be fixed
  (e.g. split ViewBuilder bodies, AnyView/Group, helper functions). Record findings in SUMMARY.
- D-05: Runtime smoke test in tart VM `sequoia-sirena` (macOS 15.7.7, admin/admin, /Applications/tart.app,
  disk on Midias drive — if unmounted, record human_needed). Build via Scripts/build-app.sh, copy app in,
  launch with `tart exec`, convert a short generated clip, `screencapture` in guest; also check file
  panels open as sheets and Dock badge during encode. Shut VM down afterwards.
- D-06: Build/test with DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer. Conventional commits.

## Claude's Discretion
Helper names, file layout, VM automation details.

## Deferred
Release docs/DMG (Phase 4).
