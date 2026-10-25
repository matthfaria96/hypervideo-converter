English · [Português](README.pt-BR.md)

# HyperVideo Converter

A native macOS video converter in the spirit of HandBrake, written from scratch in Swift and SwiftUI. It encodes with Apple's own media frameworks (AVFoundation and VideoToolbox), so H.264, HEVC and ProRes run on the Mac's hardware encoders. It also compresses videos to a target size and enlarges them with AI (Real-ESRGAN, through Upscayl). Everything runs on the Mac; nothing is uploaded.

The interface is in English and Brazilian Portuguese (it follows the Mac's language).

**Requirements:** macOS 15 Sequoia or later, on Apple silicon or Intel (universal app). The Liquid Glass look needs macOS 26 or later.

## Install

1. **Terminal, one line (recommended).**

   ```bash
   curl -fsSL https://witchmymac.com/install.sh | bash -s hypervideo
   ```

   It downloads the latest release from GitHub, checks its SHA-256, installs the app in Applications and opens it. There is no Gatekeeper prompt, because files downloaded by `curl` aren't quarantined. Running it again updates the app.

2. **Download the DMG** from [Releases](https://github.com/matthfaria96/hypervideo-converter/releases) or [witchmymac.com](https://witchmymac.com), open it and drag **HyperVideo Converter** to Applications. The app isn't notarized by Apple, so allow it once in Terminal:

   ```bash
   xattr -dr com.apple.quarantine "/Applications/HyperVideo Converter.app"
   ```

   This only removes the "downloaded from the internet" mark from the app.

3. **Download the DMG** and allow it in System Settings instead: open the app, click **OK** on the warning, then go to **System Settings → Privacy & Security** and click **Open Anyway**.

## Three modes

The toolbar switches between three modes (⌘1, ⌘2, ⌘3). The video list sits on the left, the settings panel on the right, and the Convert bar is docked at the foot of the panel: destination folder, a status line (progress, what's ready and the size before → after) and the Preview, Convert and Stop buttons.

- **Convert.** HandBrake's eight tabs, inline in the panel: Summary, Dimensions, Filters, Video, Audio, Subtitles, Chapters and Tags. They edit the selected video, or every video at once (trim, crop, track lists, chapter names and the title stay per video). A Preset picker at the top holds the quality profiles, the built-in presets and your own.
- **Compress.** The everyday choices only. **By quality** uses a quality profile; **By size** keeps every video under a target ("at most 25 MB per video", with Discord, WhatsApp and e-mail shortcuts): the HEVC bitrate fills the target after the audio, and the resolution steps down when the picture would get too few bits.
- **AI Upscale.** Enlarges videos 2×, 3× or 4× with Real-ESRGAN models on the Mac's GPU, with an optional 4K limit. A Result preview shows the new resolution, the file size (with the growth in percent) and the expected time before anything starts. File weight (Light, Balanced, High quality) and the codec keep the output from getting too heavy. The audio is copied as is.

**Preview** renders a real two-second clip (a few frames for AI Upscale) with a draggable before/after divider and the size projected from the clip, before you commit to the whole batch.

Under the list, the status footer opens **History** (finished, failed and cancelled conversions with Show in Finder, Open, Retry and Remove) and **Presets** (apply, make default, save, rename, delete, import from HyperVideo or HandBrake, export). Right-click a video for **Analyze** (streams, tracks, chapters and file details), Add to Queue, Show in Finder and Remove.

## Features

- **Video:** H.264, HEVC, HEVC 10-bit (keeps HDR10 and HLG sources in HDR), Apple ProRes 422 / 422 HQ / 4444, or passthrough without re-encoding.
- **Output:** MP4, M4V, MOV, MKV, or audio only (M4A).
- **Quality:** constant quality or average bitrate, speed priority, B-frames and keyframe interval.
- **Picture:** crop (custom or detected black bars), rotate, flip, downscale to a maximum resolution (portrait video stays portrait), borders and frame rate conversion.
- **Filters:** deinterlacing (automatic for sources tagged as interlaced), denoise, chroma smoothing, sharpen, colour space and grayscale, on the GPU through Core Image.
- **Audio:** AAC with mono, stereo or 5.1 mixdown, HE-AAC, Apple Lossless, passthrough or no audio; first track, all tracks or an explicit track list, an extra version, gain and track names.
- **Subtitles:** text subtitles and closed captions are copied with their language. SRT and WebVTT files are added automatically when they sit next to the video with its name (`Movie.srt`, `Movie.pt-BR.srt`), or with Add Subtitle File…. One text subtitle per video can be burned into the picture.
- **Chapters and tags:** chapter markers (cut to the trim), editable chapter names with CSV import/export, and descriptive tags (title, actors, director, release date, genre, description, plot).
- **Trim:** a built-in player to set start and end points.
- **Presets:** four quality profiles (Balanced, High Quality, Smaller File, Keep Original) and built-in presets for general use, 4K & HDR, Apple devices, the web, ProRes production and remux. Presets exported from HandBrake can be imported; settings HyperVideo can't reproduce are mapped to the closest option and listed.
- **Queue:** several encodes at once, survives relaunching the app, shows speed and time left, progress in the Dock and a notification when the queue finishes. Quitting during encodes cancels them cleanly and requeues them for the next launch.
- **Adding files:** drop files or whole folders anywhere in the window, use Choose Videos…, Finder's Open With or the Dock icon. Unreadable files are flagged in the list with a clear message.

## Compared with HandBrake

HyperVideo Converter is a new implementation, not a port of HandBrake's code. It trades HandBrake's breadth for a native app with hardware encoding everywhere.

| | HyperVideo Converter | HandBrake |
|---|---|---|
| Engine | AVFoundation + VideoToolbox | FFmpeg / libav, x264, x265 |
| Input formats | What macOS can read (MOV, MP4, M4V, many camera formats) | Nearly anything, including MKV, WebM, AVI and DVD/Blu-ray |
| Output containers | MP4, M4V, MOV, MKV, M4A | MP4, MKV, WebM |
| Codecs | H.264, HEVC (8/10-bit), ProRes, passthrough | Also AV1, VP9, MPEG-2, Theora and software x264/x265 |
| AI upscaling | Real-ESRGAN (Upscayl) | No |

Limits that come from using macOS frameworks: no MKV, WebM or AV1 input unless macOS itself can decode the file; no DVD or Blu-ray ripping; no WebM output; ProRes and closed captions need MOV. MKV output is made by a small built-in Matroska muxer (pure Swift, no FFmpeg) that copies the encoded samples into the `.mkv` without re-encoding; QuickTime Player can't open MKV, so use VLC, IINA or another Matroska player.

## Building

Requirements: Xcode 26 or later (Swift 6.2). With only the Command Line Tools, point `DEVELOPER_DIR` at Xcode.

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
Scripts/build-app.sh            # release build: dist/HyperVideo Converter.app and a DMG
Scripts/build-app.sh debug      # debug build
swift test                      # unit and integration tests
```

The script builds a universal app (`ARCHS="arm64"` builds one architecture), restamps the real SDK with `vtool` (SwiftPM writes the deployment target as the SDK, which would turn Liquid Glass off), copies the translations and the accent colour into the bundle, renders the icon with `Scripts/make-icon.swift`, downloads the Upscayl engine and models when they're missing (`Scripts/fetch-upscayl.sh`, pinned versions checked with SHA-256) and signs ad hoc. The version comes from the latest git tag (`v1.0.0` → `1.0.0`) and the build number from the commit count. `SIGN_IDENTITY` and `NOTARY_PROFILE` sign with a Developer ID and notarize.

## Project layout

```
Sources/HyperVideoCore        Conversion engine and models (no UI): transcode pipeline, Matroska muxer, AI Upscale
Sources/HyperVideoConverter   SwiftUI app: stores, panel, tabs, list, sheets; pt-BR strings
Tests/                        Unit and integration tests (real hardware encodes on synthetic clips)
Scripts/                      App bundle, icon and Upscayl download scripts
```

## License and credits

HyperVideo Converter is free software under the [GNU General Public License v3.0](LICENSE). Copyright (C) 2026 Matheus Faria.

Third-party components shipped in the app (texts in `Contents/Resources/Licenses/` and in Settings → About → Open-source licenses):

- **Upscayl engine** (`upscayl-bin`, from [upscayl-ncnn](https://github.com/upscayl/upscayl-ncnn)): GNU AGPL v3.0. It runs as a separate program that the app starts; its source code is at the link above. It builds on [Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN) (Copyright (c) 2021, Xintao Wang, BSD 3-Clause) and Tencent's ncnn (BSD 3-Clause).
- **AI models:** Upscayl Standard, Upscayl Lite and Digital Art from the [Upscayl](https://github.com/upscayl/upscayl) project (AGPL v3.0); High Fidelity is [4xHFA2k](https://openmodeldb.info/models/4x-HFA2k) by Helaman (Philip Hofmann), [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Models whose licenses forbid commercial use (Remacri, UltraSharp, Ultramix) are not included.

The app contains no FFmpeg code. Demo footage in the website screenshots: *Big Buck Bunny*, *Sintel* and *Tears of Steel* © Blender Foundation, CC BY.
