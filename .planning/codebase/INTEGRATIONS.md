# External Integrations

**Analysis Date:** 2026-10-19

## APIs & External Services

**Network services:**
- None. The app makes no network calls; all transcoding is local via AVFoundation/VideoToolbox.

**System services:**
- UserNotifications - queue completion alerts
  - Client: `UNUserNotificationCenter` in `Sources/HyperVideoConverter/Stores/Notifier.swift` (guarded because it traps without an app bundle, e.g. `swift run`)
  - Auth: user permission prompt (`.alert`, `.sound`)
- NSWorkspace - Finder reveal / open destination folder (`Stores/SystemIntegration.swift`, `Views/Workspace/BottomBar.swift`), power-off observation for safe quit (`App/QuitCoordinator.swift`)
- Launch Services - document types registered in `Resources/Info.plist` (videos as Alternate viewer, folders)

**File format interop:**
- HandBrake preset JSON import - `Sources/HyperVideoCore/Models/HandBrakePresets.swift`
- Subtitle files (SRT etc.) - `Sources/HyperVideoCore/Engine/SubtitleParser.swift`, `Models/SubtitleFile.swift`
- Matroska output via custom writer - `Sources/HyperVideoCore/Engine/Matroska/`

## Data Storage

**Databases:**
- None

**File Storage:**
- Local filesystem only
  - JSON documents in Application Support - `Sources/HyperVideoConverter/Stores/Persistence.swift`, `PresetStore.swift`, `QueueStore.swift` (debounced writes via `CoalescingSaver.swift`)
  - Security-scoped/bookmark data for file access persistence - `Sources/HyperVideoCore/Engine/FileBookmarks.swift`
  - `UserDefaults.standard` for preferences

**Caching:**
- None

## Authentication & Identity

**Auth Provider:**
- Not applicable

## Monitoring & Observability

**Error Tracking:**
- None

**Logs:**
- OSLog `Logger` subsystem `com.hypervideo.converter`, category `app` (`Stores/Persistence.swift`)

## CI/CD & Deployment

**Hosting:**
- Local build to `dist/` (`.app` + `.dmg`) via `Scripts/build-app.sh`; distributed through external site release links

**CI Pipeline:**
- None (no `.github/workflows`)

**Signing/Notarization:**
- `codesign` with `SIGN_IDENTITY` (hardened runtime) or ad-hoc; Apple notary service via `xcrun notarytool` using keychain profile `NOTARY_PROFILE`, then `stapler`

## Environment Configuration

**Required env vars:**
- None at runtime. Build-time optional: `SIGN_IDENTITY`, `NOTARY_PROFILE`

**Secrets location:**
- Notary credentials stored in the macOS keychain (notarytool profile); no secrets in repo

## Webhooks & Callbacks

**Incoming:**
- None

**Outgoing:**
- None

---

*Integration audit: 2026-10-19*
