---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: completed
stopped_at: Initialization complete
last_updated: "2026-10-23T12:35:15.781Z"
last_activity: 2026-10-25 — Release 1.0.1: in-app updates (Sparkle 2), tag v1.0.1
progress:
  total_phases: 7
  completed_phases: 3
  total_plans: 24
  completed_plans: 24
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-10-19)
**Core value:** Converting a video must never crash, lose work or hang the UI.
**Current focus:** Phase 03.1 — handbrake-parity-in-the-new-layout

## Current Position

Phase: 4 (Release) done — 1.0.0 tagged locally (v1.0.0) on master, DMG HyperVideo-1.0.0 in ~/Documents/witchmymac-release/dist; the coordinator pushes and publishes
Plan: see .planning/phases/04-release/04-SUMMARY.md
Status: 340 + 241 tests green; universal app, min macOS 15.0 (never run on macOS 15); 03.1-HUMAN-UAT.md still has manual checks
Last activity: 2026-10-24 — Release 1.0.0 prepared on master (panel pass, icon, universal build, READMEs)

Progress: [█████░░░░░] 50%

## Accumulated Context

### Roadmap Evolution

- Phase 03.1 inserted after Phase 3: User: redesign hid all HandBrake-derived settings; restore them in new visual (URGENT)
- Phase 03.1.2 inserted after Phase 03.1: User: fix all visual issues, premium Apple-native macOS 27 UI/UX with animation on every action (URGENT)
- Phase 03.1.2.1 inserted after Phase 03.1.2: User: video converter will get AI upscale like HyperImage

### Decisions

- Min macOS lowered to 15.0 (user choice)
- Fully autonomous YOLO mode (user: "faz tudo sem pedir nada")

### Blockers/Concerns

- Phase 3 (macOS 15): plans 03-01/03-02 done, 03-03 (VM verification) and VERIFICATION still open
- Phase 03.1: human UAT pending (03.1-HUMAN-UAT.md); not feasible / deferred HandBrake items are listed in HANDBRAKE-PARITY.md

## Release 1.0.1 (2026-10-25)

- In-app updates with Sparkle 2.10 (SwiftPM): `Updates/AppUpdater.swift`, "Check for Updates…" in the app menu and
  in Settings → About; feed `https://witchmymac.com/appcast/hypervideo.xml`, SU* keys in `Resources/Info.plist`.
  Test copies with another bundle id only check with `HYPERVIDEO_UPDATES=1`.
- `Scripts/build-app.sh` embeds `Sparkle.framework` in Contents/Frameworks (+ rpath) and its MIT licence.
- Released as v1.0.1 (DMG `HyperVideo-1.0.1.dmg`, signed with sign-app.sh); 1.0.0 release removed. Appcast item handed
  to the site coordinator. Users on 1.0.0 install 1.0.1 by hand once.

## Session Continuity

Last session: 2026-10-20T03:10:14.893Z
Stopped at: Initialization complete
Resume file: None
