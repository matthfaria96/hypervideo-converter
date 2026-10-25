# HyperVideo Converter — notes for Claude

- Driven by GSD: read `.planning/STATE.md` and `.planning/ROADMAP.md` first. Releases come from `master`.
- Build from the real path (`/Volumes/MacMiniDev/Moved/VSCode Temp/HyperVideo Converter`) with
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`:
  `Scripts/build-app.sh` → `dist/HyperVideo Converter.app` (universal, ad hoc, vtool restamps the SDK so Liquid
  Glass stays on). Version = latest `vX.Y.Z` tag, build = commit count. `swift test` runs both suites.
- Layout is a sibling of HyperImage Converter: toolbar mode switch (Convert / Compress / AI Upscale), list on the
  left, 400 pt settings panel on the right, Convert bar docked (opaque, fixed height) under the panel. Keep the two
  apps visually consistent; every HandBrake setting stays visible in Convert.
- Per-video settings (trim, crop, track lists, chapter names, title) are dropped by `copyingAll`; when the panel
  edits every video they must show `PerVideoHint`, never live controls (`\.editsAllVideos`).
- Testing the UI: never type or click into the owner's Mac. Copy the app, set the bundle id to
  `com.hypervideo.converter.check` (it then uses its own Application Support folder), launch with `open -g -n`
  and the launch arguments `-OpenOnLaunch '(a.mov, b.mp4)'`, `-InitialSection convert|compress|upscale`,
  `-InitialSettingsTab <tab>`, `-LaunchState converting|select|targetSize|settings`, `-ScreenshotActiveLook YES`,
  set `destinationPath` in that domain to a scratch folder, and capture with `screencapture -x -o -l <windowID>`.
  Avoid `-LaunchState preview` in the background: the sheet brought the app to the front once.
- Icon: `Scripts/make-icon.swift` masks `Resources/AppIcon.png` into the 824/1024 continuous-corner squircle.
- Third-party: Upscayl engine (AGPL-3.0, separate executable) and models; credits in README, About and
  `Resources/THIRD-PARTY-NOTICES.txt`. Only models whose licences allow redistribution are fetched.
