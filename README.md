# HyperVideo Converter

A native macOS video converter in the spirit of HandBrake, written from scratch in Swift and SwiftUI. It encodes with Apple's own media frameworks (AVFoundation and VideoToolbox), so H.264, HEVC and ProRes run on the Mac's hardware encoders, and the interface uses macOS Liquid Glass.

Requires macOS 26 or later.

## Features

- **Video:** H.264, HEVC, HEVC 10-bit (keeps HDR10 and HLG sources in HDR), Apple ProRes 422 / 422 HQ / 4444, or passthrough without re-encoding.
- **Quality:** constant quality or average bitrate, speed priority, B-frames and keyframe interval.
- **Picture:** crop, rotate, flip, downscale to a maximum resolution (never upscales; portrait video stays portrait) and frame rate conversion.
- **Filters:** deinterlacing (automatic for sources tagged as interlaced), denoise, sharpen and grayscale. They run on the GPU through Core Image.
- **Audio:** AAC with mono, stereo or 5.1 mixdown, Apple Lossless, passthrough or no audio. Keeps the first track or all of them, with their language tags.
- **Subtitles:** text subtitles and closed captions are copied with their language: none, the first track, or all of them. SRT and WebVTT files are added too: automatically when they sit next to the video and share its name (`Movie.srt`, `Movie.pt-BR.srt`), or with Add Subtitle File…. UTF-8, UTF-16 and Windows-1252 files are all read correctly. One subtitle per video (a source Timed Text track or an added file) can be **burned in**: drawn into the picture in white with a dark outline and shadow, bottom-centered, sized to the output height and wrapped to fit, timed to the trimmed output. The burned track isn't also kept as a soft track, and burn-in needs the video re-encoded (not passthrough).
- **Chapters and metadata:** chapter markers and tags are kept, adjusted to the trim.
- **Trim & preview:** a built-in player to set start and end points.
- **Presets:** 14 built-in presets (General, 4K & HDR, Apple devices, web, ProRes production and remux). You can also save, rename, import and export your own, and import presets exported from HandBrake. Settings HyperVideo can't reproduce are mapped to the closest option and listed after the import.
- **Queue:** runs several encodes at once, survives relaunching the app, and shows speed (× realtime and fps) and time left. It also shows progress in the Dock and sends a notification when a job finishes.
- **Before → after summary:** resolution, codecs, duration, track counts, and an estimated output size when the settings make it predictable.
- **Adding files:** drop files or whole folders anywhere in the window, use the Open panel, or use Finder's Open With and the Dock icon. Folders are searched recursively. When an import includes folders, a sheet asks which preset their videos get (the default preset is preselected); loose files keep the default preset.

## Compared with HandBrake

HyperVideo Converter is a new implementation, not a port of HandBrake's code. It trades HandBrake's breadth for a native app with hardware encoding everywhere.

| | HyperVideo Converter | HandBrake |
|---|---|---|
| Engine | AVFoundation + VideoToolbox | FFmpeg / libav, x264, x265 |
| Input formats | What macOS can read (MOV, MP4, M4V, many camera formats) | Nearly anything, including MKV, WebM, AVI and DVD/Blu-ray |
| Output containers | MP4, M4V, MOV, MKV | MP4, MKV, WebM |
| Codecs | H.264, HEVC (8/10-bit), ProRes, passthrough | Also AV1, VP9, MPEG-2, Theora and software x264/x265 |
| Subtitles | Copy text subtitles and captions, import SRT/WebVTT, burn in one text subtitle | Also bitmap (PGS/VobSub) burn-in and foreign audio search |
| Filters | Crop, scale, rotate, flip, blend deinterlace, denoise, sharpen, grayscale | Also Yadif/Bwdif deinterlace, detelecine, deblock, chroma smoothing and more |
| Interface | SwiftUI with Liquid Glass | Cocoa on Mac, GTK on Linux, WPF on Windows |

### Limits that come from using macOS frameworks

- **No MKV, WebM or AV1 input** unless macOS itself can decode the file. Unreadable files are rejected with a clear message when they're added.
- **No DVD or Blu-ray ripping.**
- **Output is MP4, M4V, MOV or MKV.** There's no WebM output.
- **ProRes needs the MOV container**, and so do closed captions. Apple Lossless works in MOV or MKV. The app flags these combinations before encoding.

### MKV output

AVFoundation can't write Matroska, so MKV is made in two steps: the encode goes into a hidden QuickTime movie in the job's work folder, then a small built-in Matroska muxer (pure Swift, no FFmpeg) copies the compressed samples into the `.mkv` without re-encoding. Progress covers both steps, and cancelling or a failure leaves nothing behind.

- **Video:** H.264 or H.265 (8 or 10-bit), encoded or passed through. Passthrough of other codecs (such as ProRes or MPEG-2) is refused with a message. Rotation from a passed-through source is stored as a projection roll, which FFmpeg-based players (VLC, IINA, mpv) honour.
- **Audio:** AAC and Apple Lossless, plus AC-3, E-AC-3 and MP3 when passed through, with languages and the first track marked default. AAC encoder priming is declared as a codec delay, so audio stays in sync.
- **Subtitles:** text subtitles (from the source or added SRT/WebVTT files) become SRT-style `S_TEXT/UTF8` tracks with their languages; styling is dropped. Closed captions aren't carried.
- **Chapters** are kept (cut to the trim range) when Keep Metadata is on; other metadata tags aren't written.
- The file has a SeekHead and Cues for fast seeking. macOS itself (QuickTime Player, Finder previews) can't open MKV; use VLC, IINA or another Matroska player.

## Building

Requirements: Xcode 26 or the Command Line Tools for macOS 26, with Swift 6.2.

```bash
swift build
```

To build an installable app and disk image (no Xcode project needed):

```bash
Scripts/build-app.sh            # release build
Scripts/build-app.sh debug      # debug build
```

This creates `dist/HyperVideo Converter.app` and `dist/HyperVideoConverter-<version>.dmg` (drag the app onto the Applications link inside it). The script:

- builds with `swift build`, assembles the bundle and copies any SwiftPM resource bundles;
- takes the version from the latest git tag (`v1.2.0` → `1.2.0`, `0.1.0` when there is none), uses the commit count as the build number and reads `LSMinimumSystemVersion` from `Package.swift`;
- registers video document types, so Finder's Open With lists the app;
- builds `AppIcon.icns` from `Resources/AppIcon.png` with `sips` and `iconutil`;
- signs ad hoc by default. Ad-hoc apps run on the Mac that built them; other Macs need right-click → Open the first time.

To sign for distribution, with the hardened runtime, and optionally notarize and staple:

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" Scripts/build-app.sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=my-profile Scripts/build-app.sh
```

`NOTARY_PROFILE` is a profile saved with `xcrun notarytool store-credentials`. If `notarytool` or `stapler` is missing, the script stops before building and says so; it only checks for them when notarization is requested.

## Testing

```bash
swift test
```

The suite covers geometry planning (including a pixel-exact check of the filter path), settings validation and persistence, output naming, subtitle and chapter rules, speed and size estimates, folder scanning, and HandBrake preset import. The integration tests create short synthetic clips (with audio, subtitles, chapters and interlacing) and convert them with the real hardware encoders, including trimming, deinterlacing and cancellation.

With only the Command Line Tools installed, `swift test` sometimes fails to build with "plugin for module 'TestingMacros' not found". That comes from the toolchain, not the code, and running it again works.

## Project layout

```
Sources/HyperVideoCore        Conversion engine and models (no UI)
  Engine/                     Transcode pipeline, media inspection, folder discovery
  Models/                     Settings, presets, jobs, media info, estimates
Sources/HyperVideoConverter   SwiftUI app
  Stores/                     App state, queue, presets, persistence
  Views/                      Sidebar, settings tabs, queue, presets inspector
Tests/HyperVideoCoreTests     Unit and integration tests
Scripts/                      App bundle and icon builders
```
