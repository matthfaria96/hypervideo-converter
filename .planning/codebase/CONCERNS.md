# Codebase Concerns

**Analysis Date:** 2026-10-19

No `TODO`/`FIXME`/`HACK` markers exist in `Sources/` or `Tests/`. The concerns below come from reading the engine, the queue and the import code.

## Tech Debt

**Swift 6 concurrency escape hatches in the engine:**
- Issue: The engine relies on `@unchecked Sendable` wrappers and `@preconcurrency import AVFoundation` to move non-Sendable AVFoundation objects between threads. Correctness depends on hand-written rules ("touched only from `queue`") that the compiler cannot check.
- Files: `Sources/HyperVideoCore/Engine/SamplePump.swift:22`, `Sources/HyperVideoCore/Engine/TranscodeEngine.swift:123,182-185`, `Sources/HyperVideoCore/Engine/Matroska/MatroskaRemuxer.swift:16`, `Sources/HyperVideoCore/Engine/SubtitleBurner.swift:10`, `Sources/HyperVideoCore/Engine/FilterCompositor.swift:6,35`, `Sources/HyperVideoConverter/Stores/CoalescingSaver.swift:5`, `Sources/HyperVideoConverter/Stores/JobProgress.swift:19`
- Impact: A data race added later will not produce a compiler error.
- Fix approach: Keep every new AVFoundation access inside the pump's own `DispatchQueue`. Where possible, use `Mutex` (as `CancelFlag`/`ActivityClock` do) instead of `NSLock` plus mutable vars. Do not add more `Unchecked` uses.

**Polling instead of signalling:**
- Issue: `SamplePump.whenIdle` busy-waits in 5 ms `Task.sleep` steps for up to the timeout. The stall watchdog wakes up every second.
- Files: `Sources/HyperVideoCore/Engine/SamplePump.swift:127-132`, `Sources/HyperVideoCore/Engine/TranscodeEngine.swift:92-103`
- Impact: Small CPU cost, and the code is harder to reason about.
- Fix approach: Resume a continuation from the `parked.notify` block, and race it against a timeout task.

**MKV output needs a full intermediate `.mov`:**
- Issue: The MKV output is encoded to `intermediate.mov` first and then remuxed, so the encode is written twice.
- Files: `Sources/HyperVideoCore/Engine/TranscodeEngine.swift:61-65,138-140`, `Sources/HyperVideoCore/Engine/Matroska/MatroskaRemuxer.swift`
- Impact: Uses about 2x the output size in disk space in the destination folder, and adds extra I/O time. Progress gives the remux a fixed 10% weight (`encodeShare = 0.9`).
- Fix approach: Write Matroska directly from the pumps' compressed output. Until then, check free disk space before an MKV job.

## Known Bugs

**Possible crash on a zero-byte sample during MKV remux:**
- Symptoms: The app crashes (force-unwrap of nil) when a source track contains an empty sample.
- Files: `Sources/HyperVideoCore/Engine/Matroska/MatroskaRemuxer.swift:275-278`
- Trigger: `Data(count: 0).withUnsafeMutableBytes { $0.baseAddress! }`. `baseAddress` can be nil for empty buffers. Empty text samples (subtitle gaps) are the likely source.
- Workaround: None. Fix by skipping the copy when `size == 0`, for example `guard size > 0 else { packets.append(empty packet); continue }`.

**Removing a running job does not remove it:**
- Symptoms: The user removes a running job. The task is cancelled, but the job stays in the list and is marked `.cancelled`.
- Files: `Sources/HyperVideoConverter/Stores/QueueStore.swift:185-188` (filters out `isRunning`), `:290-291` (`finish` writes `.cancelled` back)
- Trigger: Select a running job and choose Remove.
- Workaround: Remove it again after it shows as cancelled. Fix by recording "pending removal" IDs and dropping them in `finish`.

**Stuck pump threads leak forever after a stall:**
- Symptoms: After a `.stalled` error, `whenIdle` returns after 2 s. Each pump's queue keeps a block parked on `release.wait()` until the stuck AVFoundation call returns. If that call never returns, a GCD thread stays blocked and the reader and writer are never cancelled.
- Files: `Sources/HyperVideoCore/Engine/SamplePump.swift:111-126`, `Sources/HyperVideoCore/Engine/TranscodeEngine.swift:124-127`
- Trigger: An AVFoundation reader/writer deadlock, for example with many subtitle or audio tracks (see the `TranscodeError.stalled` message, `TranscodeEngine.swift:18`).
- Workaround: Restart the app. This only matters if stalls happen repeatedly.

**Stale-folder sweep can delete another encode's work folder:**
- Symptoms: `sweepStaleWorkDirectories` deletes every `.hypervideo-*` entry in each destination folder, not only the folders this process owns.
- Files: `Sources/HyperVideoConverter/Stores/QueueStore.swift:352-360`, called at `:56`, `:68` and `:348`
- Trigger: Two app instances (or a test run) writing to the same folder, or `stopImmediately` (logout) while the writer is still closing.
- Fix approach: Put the job ID in the work-folder name (`.hypervideo-<jobID>-<uuid>`) and only sweep folders whose job is not running.

**Final move fails if the destination appeared mid-encode:**
- Symptoms: The job fails with "Couldn't move the finished file into place" after the whole encode.
- Files: `Sources/HyperVideoCore/Engine/TranscodeEngine.swift:142-146`. Names are only made unique at enqueue time or on retry (`Sources/HyperVideoCore/Models/Job.swift:75-90`, `QueueStore.swift:169-183`).
- Trigger: A file with the destination name is created while the job is queued or running.
- Fix approach: Pick a unique name again just before `moveItem`, or use `replaceItemAt`.

## Security Considerations

**Sandbox detection by environment variable:**
- Risk: `isSandboxed` reads `APP_SANDBOX_CONTAINER_ID`. If this check is wrong, plain bookmarks are stored where security-scoped ones are needed, and queued jobs lose file access after a relaunch.
- Files: `Sources/HyperVideoCore/Engine/FileBookmarks.swift:7`
- Current mitigation: Bookmark resolution failure drops the file (`:29`).
- Recommendations: Add a test, or check the entitlement through `SecTask` if the app moves to the Mac App Store.

**Ad-hoc signing by default:**
- Risk: `Scripts/build-app.sh` signs ad hoc unless `SIGN_IDENTITY` is set, so Gatekeeper blocks distributed DMGs.
- Files: `Scripts/build-app.sh:7-11`
- Recommendations: Make release builds require `SIGN_IDENTITY` and `NOTARY_PROFILE`.

## Performance Bottlenecks

**Main-thread blocking calls (UI hitches):**
- Problem: Synchronous work runs on the main actor.
- Files:
  - `Sources/HyperVideoConverter/Stores/CoalescingSaver.swift:36`: `flush()` runs `queue.sync` on main at quit or logout.
  - `Sources/HyperVideoConverter/Stores/QueueStore.swift:47`: `store.load()` reads `queue.json` synchronously in `init`. This grows with up to 200 history jobs (`historyLimit`, `:20`).
  - `Sources/HyperVideoConverter/Stores/QueueStore.swift:173`: `fileExists` on main in `retry`. This is slow on network volumes.
  - `Sources/HyperVideoConverter/Stores/PresetStore.swift:84`: `Data(contentsOf:)` on main when importing presets.
  - `Sources/HyperVideoConverter/Stores/AppModel.swift:125,269` and `Sources/HyperVideoConverter/Views/Pages/FavoritesView.swift:135,155`: modal `NSOpenPanel.runModal()`.
- Improvement path: Move the loads to `Task.detached`, as `AppModel+Import.swift` already does, and use `beginSheetModal` for panels.

**Every progress tick spawns a MainActor Task:**
- Problem: `Task { @MainActor in self.updateProgress(...) }` runs per accepted tick, and each tick also calls `refreshDock()` (`SystemIntegration.updateDock`).
- Files: `Sources/HyperVideoConverter/Stores/QueueStore.swift:262-278`
- Cause: The throttle (`JobProgress.swift`) limits this, but with 4 concurrent jobs the Dock tile is redrawn often.
- Improvement path: Throttle `refreshDock` separately (for example once per 0.5 s).

**MKV remux peek scans every feed for every packet:**
- Problem: `interleave` builds a `pending` array across all feeds for each packet (O(tracks) allocations per packet). `pop()` uses `removeFirst()` on an array.
- Files: `Sources/HyperVideoCore/Engine/Matroska/MatroskaRemuxer.swift:142-150,218-222`
- Improvement path: Use a min-heap keyed by decode time and an index or deque in `TrackFeed`.

## Fragile Areas

**SamplePump / TranscodeEngine cancellation choreography:**
- Files: `Sources/HyperVideoCore/Engine/SamplePump.swift:48-133`, `Sources/HyperVideoCore/Engine/TranscodeEngine.swift:89-132`
- Why fragile: There are three ways to finish (normal end, `abort`, watchdog), and `isDone` and `completion` are two separate mutexes whose ordering matters (`:57-61`, `:100-105`). AVFoundation must not be cancelled while a pump is inside `copyNextSampleBuffer`/`append`.
- Safe modification: Keep the "take the continuation exactly once" invariant. Run `Tests/HyperVideoCoreTests/StressTranscodeTests.swift` and `SamplePumpTests.swift` after any change.
- Test coverage: The stress tests exist, but there is no deterministic test of the stall path leaking threads.

**Hand-written Matroska writer:**
- Files: `Sources/HyperVideoCore/Engine/Matroska/MatroskaWriter.swift`, `EBML.swift`, `MatroskaTrack.swift`, `AudioConfig.swift`
- Why fragile: Timestamps are in milliseconds, so precision is lost for 1/1000-incompatible frame rates (`MatroskaRemuxer.swift:244-246`). Block times are `Int16(clamping:)` relative to the cluster (`MatroskaWriter.swift:181`), which silently clamps if the flush guard at `:158` is ever bypassed. The SeekHead reserve is fixed at 160 bytes (`:43`). Codec support is limited to H.264/HEVC, AAC/ALAC/AC-3/E-AC-3/MP3 and timed text (`MatroskaRemuxer.swift:3-6`).
- Safe modification: Verify output with `Tests/HyperVideoCoreTests/MatroskaReader.swift` and an external tool (mkvinfo or ffprobe) after edits.

**Launch merge of resolved bookmarks:**
- Files: `Sources/HyperVideoConverter/Stores/QueueStore.swift:65-80`
- Why fragile: Jobs the user changes before resolution finishes keep their unresolved URLs (`before[current.id] == current`). `schedule()` is gated on `isReady`, so a slow volume delays the whole queue.

## Scaling Limits

**Concurrency:**
- Current capacity: `maxConcurrent` is clamped to 1...4 (`QueueStore.swift:133-136`). Imports inspect 4 files in parallel (`AppModel+Import.swift:9`).
- Limit: VideoToolbox hardware sessions. Extra jobs can fall back to software or fail.

**History:**
- Current capacity: 200 finished jobs (`QueueStore.swift:20`), all saved as one JSON on each change.

## Dependencies at Risk

**Platform floor macOS 26:**
- Risk: `Package.swift:7` sets `.macOS(.v26)`, so the app does not run on macOS 15 Sequoia. A sibling app (Sirena) was moved down to macOS 15. `swift-tools-version: 6.2` also requires a recent toolchain.
- Migration plan: Check uses of macOS 26-only APIs (Liquid Glass styling in `Sources/HyperVideoConverter/Views/Components/Theme.swift`) before lowering the floor.

No third-party packages are used. The only dependencies are Apple frameworks.

## Missing Critical Features

**No disk-space pre-check:** Jobs start without checking free space in the destination folder (`TranscodeEngine.swift:57-58`). MKV needs about 2x.

**Video codecs limited to VideoToolbox/AVFoundation:** Sources AVFoundation cannot read (many MKV/WebM/AVI inputs) fail with `readerFailed` at `TranscodeEngine.swift:49-53`. There is no demuxer for Matroska input.

## Test Coverage Gaps

**App UI layer:**
- What's not tested: The SwiftUI views (`Sources/HyperVideoConverter/Views/**`, about 2,500 lines) have no UI or snapshot tests. Only store logic is tested in `Tests/HyperVideoConverterTests`.
- Risk: Layout and binding regressions are not caught.
- Priority: Medium

**Remove-while-running, zero-size sample and sweep collisions:**
- What's not tested: The bugs listed above.
- Files: `Tests/HyperVideoConverterTests/QueueStoreTests.swift`, `Tests/HyperVideoCoreTests/MatroskaTranscodeTests.swift`, `Tests/HyperVideoConverterTests/QuitAndSweepTests.swift`
- Risk: Crash or lost work.
- Priority: High

**Build script:**
- What's not tested: `Scripts/build-app.sh` (copying localizations, signing, notarization) only runs by hand.
- Priority: Low

---

*Concerns audit: 2026-10-19*
