# Roadmap — v1.x Stabilize & Release

## Phases
- [x] **Phase 1: Engine robustness** — no crashes, no failed final moves, no leaked threads, disk-space check (completed 2026-10-20)
- [x] **Phase 2: Queue & responsiveness** — correct remove/sweep, nothing blocking the main thread
- [ ] **Phase 3: macOS 15 support** — deployment target 15.0 with compat helpers, verified in VM
- [ ] **Phase 4: Release** — docs, DMG, GitHub release, site link

## Phase Details

### Phase 1: Engine robustness
**Goal**: Encodes never crash or fail late for avoidable reasons.
**Depends on**: Nothing
**Requirements**: ENG-01, ENG-02, ENG-03, ENG-04
**Success Criteria**:
1. Test remuxing a track with an empty sample passes without crash
2. Test with destination created mid-encode produces a uniquely named output
3. Stall test shows reader/writer cancelled and pump completes
4. Job with insufficient free space fails before encoding with a translated message
**Plans**: 4 plans
- [x] 01-01-PLAN.md — MKV remux safe on zero-byte samples (ENG-01)
- [x] 01-02-PLAN.md — stall cancels reader/writer, no leaked pump threads (ENG-03)
- [x] 01-03-PLAN.md — unique name at final move + disk-space precheck in engine (ENG-02, ENG-04)
- [x] 01-04-PLAN.md — translated space error + real output URL in queue, full suite (ENG-02, ENG-04)

### Phase 2: Queue & responsiveness
**Goal**: The queue behaves as the user expects and the UI never hitches.
**Depends on**: Phase 1
**Requirements**: QUE-01, QUE-02, QUE-03, UI-01, UI-02
**Success Criteria**:
1. Removing a running job removes it (test)
2. Sweep leaves foreign/running work folders alone (test)
3. No synchronous file I/O or runModal on the main actor in the listed spots
**Plans**: 3 plans
- [x] 02-01-PLAN.md — remove running job + job-id work folders, scoped sweep (QUE-01, QUE-02)
- [x] 02-02-PLAN.md — async preset import + sheet panels (UI-01, UI-02)
- [x] 02-03-PLAN.md — Dock throttle + background queue.json load and retry check (QUE-03, UI-01)

### Phase 3: macOS 15 support
**Goal**: App runs on macOS 15 Sequoia and up.
**Depends on**: Phase 2
**Requirements**: CMP-01, CMP-02, CMP-03
**Success Criteria**:
1. Package.swift targets .macOS(.v15); build and all tests pass
2. `nm -u` shows no unguarded 26/27-only type descriptors
3. App launches and converts a clip in tart VM sequoia-sirena
**Plans**: TBD
**UI hint**: yes

### Phase 4: Release
**Goal**: New version available to users on the site.
**Depends on**: Phase 3
**Requirements**: REL-01, REL-02
**Success Criteria**:
1. README/site state macOS 15+
2. GitHub release with DMG exists and apps.js points to it
**Plans**: TBD

## Progress
| Phase | Plans | Status |
|---|---|---|
| 1 | 0/0 | Not started |
| 2 | 0/0 | Not started |
| 3 | 0/0 | Not started |
| 4 | 0/0 | Not started |
