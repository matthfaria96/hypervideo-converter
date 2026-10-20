# HyperVideo Converter

## What This Is
Native macOS video converter (HandBrake-style) in Swift 6 / SwiftUI, encoding with AVFoundation + VideoToolbox. Outputs MP4/MOV/M4V/MKV (own Matroska writer). UI in English and pt-BR. Distributed as DMG on the witchmymac site.

## Core Value
Converting a video must never crash, lose work or hang the UI.

## Context
- Brownfield: ~240 passing Swift Testing tests, build green. See `.planning/codebase/`.
- Sibling app Sirena was lowered to macOS 15 using `compatGlass*` helpers; same approach applies here.
- Xcode 27 SDK can silently link macOS 26/27-only symbols that crash at runtime on 15 — verify with `nm -u` and the tart VM `sequoia-sirena`.

## Requirements
### Validated (existing)
- Convert/Compress workspace, queue, presets, HandBrake preset import, subtitles/burn-in, trim, chapters, MKV output, history, notifications, pt-BR.

### Active
See REQUIREMENTS.md.

### Out of Scope
- Non-AVFoundation input demuxing (MKV/WebM/AVI input) — large feature, later milestone.
- Direct Matroska writing without intermediate .mov — replaced by disk-space check this cycle.
- UI snapshot tests.

## Key Decisions
| Decision | Rationale | Outcome |
|---|---|---|
| Lower min to macOS 15.0 | User wants pre-Liquid-Glass Macs (matches Sirena) | Pending |
| YOLO / fully autonomous | User asked to run everything without asking | Active |

## Evolution
Update at phase transitions and milestone boundaries.

*Last updated: 2026-10-19 after initialization*
