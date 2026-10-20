---
phase: 03-macos-15-support
plan: 02
subsystem: ui
tags: [macos15, swiftui, compat, nm-audit]
requires: [03-01]
provides: [UI compat helpers, symbol audit]
affects: [03-03]
key-files:
  created: [Sources/HyperVideoConverter/Views/Components/Compat.swift]
  modified: [Sources/HyperVideoConverter/Views/ContentView.swift]
decisions:
  - "Toolbar helper is a @ToolbarContentBuilder extension with if #available (compiles via LimitedAvailabilityToolbarContent); no CompatToolbarItem struct needed"
  - "SDK-inlined weak refs (_TaskValueModifier2, _TagTraitWritingModifier, ForEach/Section.create) accepted: emitted by SwiftUI @export(implementation) bodies behind their own if #available"
requirements: [CMP-02, CMP-03]
completed: 2026-10-20
---

# Phase 3 Plan 02: macOS 15 UI compat + nm audit Summary

Compat.swift (Sirena-style glass helpers + `compatHiddenSharedBackground()` toolbar helper) replaces both direct `sharedBackgroundVisibility(.hidden)` calls; full package builds for macOS 15 and the nm audit finds no strong reference to any macOS 26/27-only symbol.

## Task 1
- Compat.swift: `supportsLiquidGlass`, `compatGlass`, `compatGlassButtonStyle`, `compatGlassProminentButtonStyle`, `ToolbarContent.compatHiddenSharedBackground()`.
- ContentView: `grep -c sharedBackgroundVisibility` = 0.
- Other Views grep: only `.symbolEffect(.rotate, ...)` in WorkRows.swift (macOS 15 API, fine).
- `swift test`: HyperVideoCoreTests 160 tests / 30 suites passed; HyperVideoConverterTests 123 tests / 24 suites passed (283 total).

## Task 2: nm audit (Xcode SDK, DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer)
Deployment target: `otool -l` LC_BUILD_VERSION on debug and release binaries: `minos 15.0`.

Undefined symbols in binary (`nm -m`): debug 2162 (57 weak), release 1771 (43 weak).

Weak, 26/27-only, all checked against the SDK .swiftinterface:
| Symbol | Availability | Source | Guard |
|---|---|---|---|
| ToolbarContent.sharedBackgroundVisibility + opaque descriptor | macOS 26.0 | Compat.swift (inlined into ContentView.o in release) | `if #available(macOS 26, *)` |
| Glass, glassEffect, GlassButtonStyle, GlassProminentButtonStyle (debug only; dead-stripped in release, helpers unused) | macOS 26.0 | Compat.swift | `if #available(macOS 26, *)` |
| _TaskValueModifier2 (init, VMn, VMa, conformance) | macOS 26.4 | AnalyzeView.o via `.task(id:)` | SDK `@export(implementation)` body `if #available(macOS 26.4)` else `_TaskValueModifier` |
| _TagTraitWritingModifier (VMn, VMa, conformance) | macOS 26.0 | `.tag()` in SubtitlesTab, SettingsTabs, PreferencesView, AdvancedSettingsSheet, InspectorControls, DimensionsAudioTabs, FolderImportSheet, AnalyzeView | SDK `tag()` body `if #available(macOS 26)` else `_trait` |
| ForEach.create(_:content:), ForEach.create(_:id:content:) | macOS 26.0 | ForEach inits across Views | SDK init body `if #available(macOS 26)` |
| Section.create(isExpanded:content:header:footer:) | macOS 26.0 | FolderImportSheet.o | SDK init body `if #available(macOS 26)` / macOS 14 fallback |

Other weak refs: AVFoundation async-loading overlay (`load(_:isolation:)`, `value(of:)`, `AVPartialAsyncProperty.backDeployedKey`) — back-deploy shims; `__availability_version_check`, `swift_coroFrameAlloc`, `swift_runtimeSupportsNoncopyableTypes`, `_swift_FORCE_LOAD_*` — runtime/compiler, standard.

Strong refs: 966 unique SwiftUI/SwiftUICore/AVFoundation/AppKit/AVKit/Observation symbols demangled; 228 referenced types checked against SwiftUI+SwiftUICore interfaces: none introduced in macOS 16+ (TupleToolbarContent, LimitedAvailabilityToolbarContent, _ConditionalContent, TabContent etc. all older). Member-name check: no strongly referenced member whose only declarations are macOS 26+. No `TupleContent`, `ToolbarSpacer`, `AVVideoComposition*Configuration`, `backgroundExtensionEffect`, `scrollEdgeEffect` in any binary or per-file .o (debug and release, `nm -um`). ObjC classes all pre-15 (AVMutableVideoComposition* etc.).

Result: CLEAN, no source changes needed in Task 2. Runtime confirmation on macOS 15 is 03-03 (VM smoke test).

## Commits
- cf89d38 feat(03-02): macOS 15 UI compat helpers

## Deviations from Plan
None. Task 2 needed no code change, so it has no commit of its own.

## Self-Check: PASSED
