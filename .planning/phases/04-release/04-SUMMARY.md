# Phase 4 — Release 1.0.0 (2026-10-24)

## Git
`claude/project-thread-n53syg` fast-forwarded into `master` (master was its ancestor, nothing to merge).

## Right panel visual pass
Before: `screenshots/before-*.png`, after: `screenshots/after-*.png`.
- Convert box floated in glass over the scroll view: rows showed through around and below it, and it grew a
  line when the list was empty. Now an opaque bar docked under the panel (like HyperImage 6e78d8d) with a fixed
  status line: progress while running, otherwise why Convert is off or "N videos ready · 32 MB → ≈ 20 MB".
- Panel header kept a different height when the mode had header buttons (title jumped 3 pt): fixed 28 pt row.
- Tab bar names sat on different baselines (symbols of different heights): fixed icon box.
- Tags: each field started at a different x (label width): one 92 pt label column in a Grid; Plot editor styled.
- Before → After: labels wrapped ("Taxa de / quadros"): labels fixed, columns tightened.
- Audio track buttons were cut ("Adicion…", "Recarreg…"): ViewThatFits row → stacked.
- AI Upscale credit and its "Source code" link were on different baselines: one text with an inline link.
- Wide thumbnails pushed the duration badge out of the corner ("0:1"): inner picture clipped to the frame.
- Bug: with every video edited at once, Trim, Crop, track lists, chapter names and the title looked editable but
  their edits were dropped (they stay per video). They now show a hint to select one video.

## Functionality checked (test copy, bundle id .check, demo clips from Blender films, CC BY)
Convert (MP4/H.264, 4 clips), Compress by size (2 MB target: all ≤ 2 MB, resolution stepped down), AI Upscale
(320×180 → 640×360, 14 frames, audio copied), cancel during AI Upscale (upscayl-bin stopped, no output left),
unreadable files flagged ("Formato não suportado ou arquivo danificado"), Preview sheet (AI Upscale before/after),
Intel slice under Rosetta (convert OK). MKV, ProRes, M4A and subtitle paths are covered by the integration tests.
Tests: 340 + 241 green.

## Also
- No `NSApp.activate()` at launch for the bundled app (only the bare SwiftPM executable), so `open -g` stays behind.
- Launch args `-OpenOnLaunch` and `-ScreenshotActiveLook` for background screenshots; a copy with another bundle id
  keeps its own Application Support folder.
- Icon: plain rounded rect → Apple continuous-corner squircle (n = 5), 824/1024, same shadow and rim as HyperImage.
- Universal build by default; THIRD-PARTY-NOTICES.txt in Contents/Resources/Licenses; READMEs in EN + pt-BR.

## Open
- macOS 15: the deployment target is 15.0 but it was never run on macOS 15 (VM check 03-03 dropped by the user).
- Opening the Preview sheet from a background launch (`-LaunchState preview`) brought the app to the front once.
- 03.1-HUMAN-UAT.md manual checks still open.
