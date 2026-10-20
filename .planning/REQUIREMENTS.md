# Requirements — v1.x Stabilize & Release

## v1 Requirements

### Engine robustness (ENG)
- [x] **ENG-01**: MKV remux never crashes on zero-byte samples (MatroskaRemuxer.swift:275)
- [x] **ENG-02**: Final output move never fails because a same-name file appeared mid-encode (pick unique name at move time)
- [x] **ENG-03**: A stalled encode cancels its reader/writer and does not leak blocked threads
- [x] **ENG-04**: Jobs check free disk space in destination before starting (MKV needs ~2x) and fail with a clear, translated message

### Queue correctness (QUE)
- [x] **QUE-01**: Removing a running job cancels it and removes it from the list
- [x] **QUE-02**: Work-folder sweep only deletes folders not owned by a running job of this process
- [x] **QUE-03**: Dock progress refresh is throttled

### Responsiveness (UI)
- [x] **UI-01**: queue.json load, preset import read and retry fileExists run off the main thread
- [x] **UI-02**: Open panels use sheet presentation instead of runModal

### Compatibility (CMP)
- [ ] **CMP-01**: App builds with deployment target macOS 15.0
- [ ] **CMP-02**: Liquid Glass and other 26+ APIs go through availability-guarded compat helpers with a fallback look
- [ ] **CMP-03**: Built binary has no unguarded macOS 26/27-only symbols; app launches and converts a video in the macOS 15 VM

### Release (REL)
- [ ] **REL-01**: README and site say macOS 15+; version bumped
- [ ] **REL-02**: DMG built with Scripts/build-app.sh, GitHub release published, witchmymac apps.js link updated

## Traceability
| Req | Phase |
|---|---|
| ENG-01..04 | 1 |
| QUE-01..03 | 2 |
| UI-01..02 | 2 |
| CMP-01..03 | 3 |
| REL-01..02 | 4 |
