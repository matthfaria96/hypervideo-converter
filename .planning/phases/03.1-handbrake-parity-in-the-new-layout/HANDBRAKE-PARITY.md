# HandBrake parity inventory (HBP-01)

**Reference:** HandBrake.app 1.10.2 (macOS), `/Applications/HandBrake.app`
**App:** HyperVideo Converter at commit c5c939c (after redesign 08edcbf + phase 3 compat work)
**Date:** 2026-10-22

## Sources and method

| Source | How | What it gave |
|---|---|---|
| Nib strings (`Contents/Resources/pt_BR.lproj/*.strings`) | `grep` of the `/* Class = …; title = "English"; ObjectID … */` comments in each `.strings` file. They hold the English Base.lproj text next to the pt-BR translation. | Every label, menu item and tooltip of the tabs: HBSummaryViewController, HBPictureViewController, HBCroppingView, HBFiltersViewController, Video, Audio, AudioDefaults, Subtitles, SubtitlesDefaults, ChaptersTitles, HBTrackTitleViewController, MainWindow (tab names, range) |
| HandBrakeKit binary (`Frameworks/HandBrakeKit.framework/Versions/A/HandBrakeKit`) | `strings -a` filtered for preset keys, `HB*` classes and filter/encoder names | The full preset JSON key set (`Picture*`, `Video*`, `Audio*`, `Subtitle*`, `ChapterMarkers`, `MetadataPassthrough`, `AlignAVStart`, `Mp4HttpOptimize`, `Mp4iPodCompatible`, `InlineParameterSets`), the model classes (`HBPicture`, `HBFilters`, `HBVideo`, `HBAudioTrack`, `HBAudioDefaults`, `HBSubtitlesTrack`, `HBSubtitlesDefaults`, `HBChapter`, `HBMetadata`, `HBRange`), and the value names (`nlmeans`, `hqdn3d`, `unsharp`, `lapsharp`, `bwdif`, `yadif`, `decomb`, `detelecine`, `comb_detect`, `chroma_smooth`, `deblock`, `colorspace`, `grayscale`, `copy:aac` … `copy:truehd`, `ca_aac`, `ca_haac`, mixdowns `dpl2`, `5point1`, `6point1`, `7point1`) |
| REA (`mcp__rea__open_binary` on HandBrakeKit) | Tried `get_objc_classes` and `search_strings` | The Hopper provider timed out during initial analysis (`provider_timeout` after 120 s). The same evidence came from `strings` and the nib strings instead. |
| Our code | `Sources/HyperVideoCore/Models/*.swift`, `Engine/*`, `HandBrakePresets.swift`, `Views/*` | Current coverage |

**Note on Tags:** HandBrake for macOS 1.10.2 has no Tags tab. The main window's tabs are Summary, Dimensions, Filters, Video, Audio, Subtitles and Chapters (from MainWindow.strings `NSTabViewItem`). Tags exist in the GTK/Windows builds and in HandBrakeKit's `HBMetadata` (the job's `Metadata` dictionary: Name, Artist, AlbumArtist, Composer, ReleaseDate, Comment, Album, Genre, Description, LongDescription). We add a Tags tab anyway, as the request asks.

## Legend

| Mark | Meaning |
|---|---|
| **PV** | present and visible in the redesigned window (sidebar / workspace / inspector) |
| **PH** | present but hidden: only in the AdvancedSettingsSheet (⌘E / right-click / small button) |
| **MF** | missing, feasible with AVFoundation, VideoToolbox, Core Image or AudioToolbox. Phase target unless marked *(deferred)* |
| **NF** | not feasible on Apple's frameworks (reason given) |

Every PH item becomes PV in this phase because the per-video tabs move inline.

## Summary tab

| ID | HandBrake setting (preset key) | Ours | Status | Notes / plan |
|---|---|---|---|---|
| SUM-01 | Format: MP4 / MKV / WebM (`FileFormat`) | `container` mp4/m4v/mov/mkv | PV | Inspector "Output Format" |
| SUM-02 | WebM output (`av_webm`) | — | NF | WebM needs VP8/VP9/AV1 + Opus/Vorbis; VideoToolbox has no VP9/AV1 *encoder* and AVAssetWriter can't write WebM |
| SUM-03 | Web Optimized (`Optimize` / `Mp4HttpOptimize`) | `optimizeForWeb` | PH | `shouldOptimizeForNetworkUse` |
| SUM-04 | Align A/V Start (`AlignAVStart`) | — | MF | Start every track at the first video frame: drop audio before it and shift the session start. Pure timing rule in the pumps. |
| SUM-05 | Passthru Common Metadata (`MetadataPassthrough`) | `keepMetadata` | PV | Inspector "Remove metadata" (inverse) |
| SUM-06 | iPod 5G Support (`Mp4iPodCompatible`) | — | NF | Needs a private `uuid` atom that AVAssetWriter can't write. The device is from 2006. |
| SUM-07 | Tracks / Filters / Size summary + preview | Before → After grid | PH | Summary tab |

## Dimensions tab (HBPictureViewController + HBCroppingView)

| ID | HandBrake setting | Ours | Status | Notes / plan |
|---|---|---|---|---|
| DIM-01 | Rotation 0/90/180/270 (`PictureRotate angle=`) | `rotation` | PH | |
| DIM-02 | Flip horizontal (`PictureRotate hflip=`) | `flipHorizontal` | PH | |
| DIM-03 | Cropping: Custom (`PictureCropMode`=1, `Picture*Crop`) | `crop` | PH | |
| DIM-04 | Cropping: Automatic / Conservative (`PictureCropMode` 0/2) | — | MF | Black-bar detection on ~10 frames from AVAssetImageGenerator, luma threshold per row/column with Core Image area-average. Conservative = smallest bars found, Automatic = most common bars. `CropMode` enum + `CropDetector`. |
| DIM-05 | Cropping: None | `crop = .zero` | PH | Becomes CropMode.none |
| DIM-06 | Resolution limit 480p…2160p (`PictureWidth/Height`) | `maxResolution` | PV | Inspector "Resolution" |
| DIM-07 | Resolution limit 4320p 8K and Custom max width/height | — | MF | Add `.uhd4320`. Optional custom max width/height *(deferred: the presets cover common sizes)* |
| DIM-08 | Allow Upscaling (`PictureAllowUpscaling`) | never upscales | MF | `allowUpscaling` flag in GeometryPlanner |
| DIM-09 | Optimal Size (`PictureUseMaximumSize`) | always "fit within limit" | PV (implicit) | Our limit already uses the largest size that fits |
| DIM-10 | Anamorphic Automatic / None / Custom + pixel aspect (`PicturePAR`, `PicturePARWidth/Height`) | always square pixels at the display size | MF | `Anamorphic` none/automatic: automatic keeps the storage width and writes `AVVideoPixelAspectRatioKey`. Custom PAR *(deferred)* |
| DIM-11 | Scaled size / display size steppers, modulus (`PictureModulus`) | — | MF *(deferred)* | Output dimensions are already rounded to even numbers; free sizing is a power-user edge |
| DIM-12 | Borders / Fill: None, Height (letterbox), Width (pillarbox), Width & Height (`PicturePadMode`, `PicturePad*`) | — | MF | `Padding` model + FrameFilter compositing over a coloured canvas; target size = limit box |
| DIM-13 | Border color Black / White / Gray / Dark Gray / Custom (`PicturePadColor`) | — | MF | Named colours + custom hex |
| DIM-14 | Source / final dimensions read-outs | Summary Before → After | PH | Also shown in the Dimensions tab |

## Filters tab (HBFiltersViewController)

| ID | HandBrake setting | Ours | Status | Notes / plan |
|---|---|---|---|---|
| FIL-01 | Detelecine Off/Default/Custom (`PictureDetelecine`) | — | NF | Inverse telecine (pullup) needs to look at and drop frames across time. The Core Image compositor sees one output frame per request, and AVVideoComposition can't remove frames. |
| FIL-02 | Interlace Detection (comb detect) (`PictureCombDetectPreset`) | `deinterlace = .auto` acts on the source's field flag | PH (partial) | Per-frame comb analysis isn't done. Automatic uses the container's interlace flag. |
| FIL-03 | Deinterlace: Off / Yadif / Bwdif / Decomb (`PictureDeinterlaceFilter`) | `deinterlace` off/auto/always, blend | PH (partial) | We have one spatial blend. Yadif/Bwdif/Decomb are temporal (they need the previous and next field) → NF as distinct algorithms. Imports map all of them to our deinterlace. |
| FIL-04 | Deinterlace preset Default/Skip Spatial/EEDI2/Bob (`PictureDeinterlacePreset`) | — | MF (Bob only) | Add `bob` = line-double one field (Core Image: sample the even lines and scale up). EEDI2 → NF. |
| FIL-05 | Denoise filter NLMeans / HQDN3D (`PictureDenoiseFilter`) | `denoise` strength via CINoiseReduction | PH (partial) → MF | `DenoiseFilter` nlmeans (CINoiseReduction, edge-preserving) / hqdn3d (CIMedianFilter + light Gaussian blend: faster and softer) |
| FIL-06 | Denoise preset ultralight/light/medium/strong/stronger/verystrong (`PictureDenoisePreset`) | off/light/medium/strong | PH (partial) → MF | Extend FilterStrength to the 6 HandBrake levels (keeps old raw values) |
| FIL-07 | Denoise tune none/film/grain/highmotion/animation/tape/sprite (`PictureDenoiseTune`) | — | MF | Tune scales the parameters (film 1.0, grain = chroma only through a luminosity blend, highmotion = luma weight, animation 0.8, tape 1.2, sprite = median 1 px) |
| FIL-08 | Chroma Smooth preset + tune (`PictureChromaSmoothPreset/Tune`) | — | MF | Blur the picture and keep only its colour (CIColorBlendMode of blurred over original), radius by preset; tune = blur width (tiny…wide) |
| FIL-09 | Sharpen filter Unsharp / Lapsharp (`PictureSharpenFilter`) | `sharpen` via CISharpenLuminance | PH (partial) → MF | `SharpenFilter` unsharp → CIUnsharpMask, lapsharp → CISharpenLuminance |
| FIL-10 | Sharpen preset ultralight…verystrong + tune (unsharp: ultrafine/fine/medium/coarse/verycoarse; lapsharp: film/grain/animation/sprite) (`PictureSharpenPreset/Tune`) | off/light/medium/strong | MF | Same 6 levels; tune → radius (unsharp) or intensity multiplier (lapsharp) |
| FIL-11 | Deblock (`PictureDeblockPreset/Tune`) | — | NF | Real deblocking needs the codec's block grid and quantiser, which the decoder doesn't hand over. A blur would only soften. Imports note it. |
| FIL-12 | Colorspace bt709 / bt601 / bt2020 (`PictureColorspacePreset`) | output is always Rec.709 for SDR, source colours for 10-bit | MF | `ColorspaceTarget` off/bt709/bt601-525/bt601-625/bt2020: sets the composition/writer colour properties so Core Image converts |
| FIL-13 | Grayscale (`VideoGrayScale`) | `grayscale` | PH | |

## Video tab

| ID | HandBrake setting | Ours | Status | Notes / plan |
|---|---|---|---|---|
| VID-01 | Encoder: VideoToolbox H.264 / H.265 / H.265 10-bit (`vt_h264`, `vt_h265`, `vt_h265_10bit`) | `videoCodec` h264/hevc/hevc10 | PV | |
| VID-02 | Encoder: x264, x265, NVENC, QSV | mapped to VT | NF | Software/third-party encoders; imports map them to the VT equivalent with a note |
| VID-03 | Encoder: ProRes 422 / HQ / 4444 | proRes422/HQ/4444 | PV | |
| VID-04 | Encoder: ProRes 422 LT / Proxy (`vt_prores_lt`, `vt_prores_proxy`) | — | MF | `AVVideoCodecType.proRes422LT`, `.proRes422Proxy` |
| VID-05 | Encoder: AV1 / VP8 / VP9 / Theora / MPEG-2 / MPEG-4 / FFV1 | — | NF | No Apple encoders for these |
| VID-06 | Passthrough video | `.passthrough` | PV | HandBrake doesn't have it; we keep it |
| VID-07 | Framerate list: Same as source, 5, 10, 12, 15, 23.976, 24, 25, 29.97, 30, 48, 50, 59.94, 60, 72, 75, 90, 100, 120 (`VideoFramerate`) | source, 23.976, 24, 25, 29.97, 30, 50, 59.94, 60 | PH (partial) → MF | Add the missing rates |
| VID-08 | Framerate mode Constant / Peak / Variable (`VideoFramerateMode` cfr/pfr/vfr) | always constant | MF | Variable: composition `sourceTrackIDForFrameTiming`. Constant: frameDuration (as now). Peak: source timing + drop frames closer than 1/peak (`PeakRateLimiter` in the video pump) |
| VID-09 | Constant Quality RF (`VideoQualityType`=2, `VideoQualitySlider`) | quality 0.2–1.0 | PV | Inspector slider; import maps RF |
| VID-10 | Average Bitrate (`VideoAvgBitrate`) | `.averageBitrate` | PH | Video tab |
| VID-11 | Multi-pass / Turbo first pass (`VideoMultiPass`, `VideoTurboMultiPass`) | — | MF *(deferred)* | AVAssetWriterInput's multi-pass API needs the reader re-run over each pass's time ranges, and VideoToolbox's hardware H.264/HEVC sessions often report `canPerformMultiplePasses == false`. Too risky for this phase. |
| VID-12 | Encoder preset (VT: speed / quality) (`VideoPreset`) | `prioritizeSpeed` toggle | PH → MF | `EncoderSpeed` speed/balanced/quality: PrioritizeEncodingSpeedOverQuality and MaximizePowerEfficiency off for quality |
| VID-13 | Encoder tune (`VideoTune`) | — | NF | VideoToolbox has no tunes (HandBrake's vt encoders list none) |
| VID-14 | Encoder profile: H.264 auto/baseline/main/high; H.265 auto/main/main10 (`VideoProfile`) | fixed High / Main / Main10 | MF | `VideoProfile` + `AVVideoProfileLevelKey` / `kVTProfileLevel_*` |
| VID-15 | Encoder level: auto, 3.0…5.2 for H.264 (`VideoLevel`) | Auto | MF | H.264 levels via `kVTProfileLevel_H264_<Profile>_<Level>`; HEVC: VideoToolbox only has AutoLevel → auto only |
| VID-16 | Fast Decode (x264 tune) | — | NF | x264 only; the B-frames switch (VID-18) is the closest VT control |
| VID-17 | Additional encoder options string (`VideoOptionExtra`) | keyframe interval + B-frames | PH (partial) | Free-form x264 options are NF. VT's equivalents are in Advanced. |
| VID-18 | (VT) keyframe interval, B-frames | `keyframeIntervalSeconds`, `allowBFrames` | PH | |
| VID-19 | Color range limited/full (`VideoColorRange`) | limited | MF *(deferred)* | Needs full-range pixel formats through the whole compositor and writer path, with HDR implications |
| VID-20 | Passthru HDR dynamic metadata (`VideoPasshtruHDRDynamicMetadata`) | HDR kept on 10-bit path | PV (implicit) | |

## Audio tab (Audio + AudioDefaults)

| ID | HandBrake setting | Ours | Status | Notes / plan |
|---|---|---|---|---|
| AUD-01 | Track list: each source track added as a row with its own settings | one global encoding for first/all tracks | MF | `AudioTrackSetting` list per video: source track index, encoder, mixdown, sample rate, bitrate, gain, name. An empty list means "use the selection behaviour". |
| AUD-02 | Track Selection Behavior None / First matching languages / All matching languages + Languages list (`AudioTrackSelectionBehavior`, `AudioLanguageList`) | first / all | PH (partial) → MF | `AudioTrackSelection` none/first/all + `audioLanguages: [String]` filter |
| AUD-03 | Encoder AAC (CoreAudio) (`ca_aac`, `av_aac`) | aac | PH | |
| AUD-04 | Encoder HE-AAC (`ca_haac`, `fdk_haac`) | — | MF | `kAudioFormatMPEG4AAC_HE` |
| AUD-05 | Encoder ALAC (`alac`, `alac24`) | alac | PH | |
| AUD-06 | Passthru: Auto Passthru + allowed codecs (AAC, AC3, E-AC3, DTS, DTS-HD, TrueHD, MP3, MP2, FLAC, Opus, ALAC, Vorbis) + Passthru Fallback (`AudioAllow*Pass`, `AudioEncoderFallback`, `copy`) | `.passthrough` copies anything | MF | `AutoPassthru`: copy only codecs in the allowed set that the container accepts, otherwise encode with the fallback |
| AUD-07 | Encoder AC3 / E-AC3 / MP3 / MP2 / Vorbis / Opus / FLAC / TrueHD | — | NF | AVAssetWriter has no AC-3/E-AC-3/MP3/MP2/Vorbis encoder. Opus/FLAC can be encoded by AudioToolbox but AVAssetWriter won't put them in MP4/MOV reliably and our MKV path only remuxes AAC/ALAC/AC-3/MP3. Passthru of these sources stays possible (AUD-06). |
| AUD-08 | Mixdown Mono / Stereo / 5.1 | mono/stereo/surround51 | PH | |
| AUD-09 | Mixdown 7.1 (`7point1`) | — | MF | AAC 8 channels, layout `kAudioChannelLayoutTag_MPEG_7_1_C` |
| AUD-10 | Mixdown Left only / Right only / 6.1 / Dolby Surround / Dolby Pro Logic II | — | NF | Dolby matrix encoding isn't in AudioToolbox. Left/Right-only and 6.1 need custom channel maps that AVAssetReaderAudioMixOutput can't express. |
| AUD-11 | Sample rate Auto / 8 / 11.025 / 12 / 16 / 22.05 / 24 / 32 / 44.1 / 48 kHz (`AudioSamplerate`) | always 48 kHz | MF | `AudioSampleRate` enum; auto = source rate clamped to what AAC takes |
| AUD-12 | Bitrate (`AudioBitrate`) | 64–640 kbit/s | PH | |
| AUD-13 | Gain −20…+20 dB (`AudioTrackGainSlider`) | — | MF | Scale the float PCM samples between reader and writer (`AudioGain` sample transform in the pump) |
| AUD-14 | DRC (`AudioTrackDRCSlider`) | — | NF | Uses the AC-3 decoder's compression metadata. Apple's AC-3 decoder doesn't expose it. |
| AUD-15 | Track name / Autonaming / Passthru track name (`AudioTrackName`, `AudioTrackNamePassthru`, `AudioAutomaticNamingBehavior`) | — | MF | Writer input metadata `quickTimeUserDataTrackName` / `commonIdentifierTitle` |
| AUD-16 | Use only first encoder for secondary audio (`AudioSecondaryEncoderMode`) | extra version applies to every track | MF | `extraAudioFirstTrackOnly` flag |
| AUD-17 | A second encoder per track (`AudioList` second entry) | `extraAudio` | PH | |
| AUD-18 | Quality-based VBR (`AudioTrackQualityEnable`), compression level, dither, normalize mix | — | NF *(minor)* | Not exposed by AVAssetWriter's AAC settings in a way that matches HandBrake |

## Subtitles tab (Subtitles + SubtitlesDefaults)

| ID | HandBrake setting | Ours | Status | Notes / plan |
|---|---|---|---|---|
| SUB-01 | Track list with per-track include | none/first/all | PH (partial) → MF | `SubtitleTrackSetting` per source track: include, default, forced only. Empty list = selection behaviour. |
| SUB-02 | Selection behavior None / First / All matching languages + languages (`SubtitleTrackSelectionBehavior`, `SubtitleLanguageList`) | none/first/all | PH (partial) → MF | Shares the language filter with audio |
| SUB-03 | Burned In (one track) (`SubtitleBurnBehavior`) | `burnIn` track/file | PH | |
| SUB-04 | Default flag | none default | MF | Alternate group `defaultInput` = flagged track; it stays enabled |
| SUB-05 | Forced subtitles only | — | MF | Keep a track only if it carries `AVMediaCharacteristic.containsOnlyForcedSubtitles`; mark the written track forced-only |
| SUB-06 | Foreign Audio Search (`SubtitleAddForeignAudioSearch`) | — | NF | Scans VobSub/PGS bitmap subtitles for forced runs; AVFoundation can't decode bitmap subtitles |
| SUB-07 | Add Closed Captions when available (`SubtitleAddCC`) | CC kept in MOV | PH | |
| SUB-08 | Burn DVD / Blu-ray subtitles (`SubtitleBurnDVDSub`, `SubtitleBurnBDSub`) | — | NF | Bitmap subtitles can't be decoded |
| SUB-09 | Add external SRT/SSA track | SRT/WebVTT files | PH | SSA/ASS styling is NF (text only) |
| SUB-10 | External SRT offset ms | — | MF | `SubtitleFile.offsetMs`, shifts cues |
| SUB-11 | External SRT language | `SubtitleFile.language` | PH | |
| SUB-12 | External SRT character encoding | UTF-8 / auto | MF *(deferred)* | Parser assumes UTF-8 with Latin-1 fallback |
| SUB-13 | Track name (`SubtitleTrackNamePassthru`) | — | MF | Same mechanism as AUD-15 |

## Chapters tab (ChaptersTitles)

| ID | HandBrake setting | Ours | Status | Notes / plan |
|---|---|---|---|---|
| CHP-01 | Create chapter markers (`ChapterMarkers`) | tied to keepMetadata | MF | Own `chapterMarkers` flag (default on) |
| CHP-02 | Chapter list with timestamp, duration, editable title | read-only list in Summary | PH (read-only) → MF | `chapterTitles: [String]` overrides per video, used by the MP4/MOV chapter track and the MKV remuxer |
| CHP-03 | Import / Export chapter names CSV | — | MF | HandBrake CSV format `number,"title"` |
| CHP-04 | Range: chapters / seconds / frames (MainWindow) | trim in seconds | PH (seconds) / MF (chapters) | Pick start/end chapter in Chapters tab → sets trim |

## Tags (HandBrake GTK/Windows, HBMetadata)

| ID | HandBrake setting | Ours | Status | Notes / plan |
|---|---|---|---|---|
| TAG-01 | Title | — | MF | `MetadataTags` → AVMetadataItems (common + iTunes keys) on the writer; MKV via MatroskaWriter tags |
| TAG-02 | Actors / Artist | — | MF | |
| TAG-03 | Director | — | MF | `quickTimeMetadataDirector` / iTunes `©dir` |
| TAG-04 | Release date | — | MF | |
| TAG-05 | Comment | — | MF | |
| TAG-06 | Genre | — | MF | |
| TAG-07 | Description | — | MF | |
| TAG-08 | Plot (long description) | — | MF | iTunes `ldes` |

## Counts

Rows are HandBrake settings. A row that is partly present and partly missing is counted under each status that applies, so the totals add up to more than the number of rows.

| Status | Count | IDs |
|---|---|---|
| Present-visible (PV) | 9 | SUM-01, SUM-05, DIM-06, DIM-09, VID-01, VID-03, VID-06, VID-09, VID-20 |
| Present-hidden (PH, incl. partial) | 32 | SUM-03, SUM-07, DIM-01, DIM-02, DIM-03, DIM-05, DIM-14, FIL-02, FIL-03, FIL-05, FIL-06, FIL-09, FIL-13, VID-07, VID-10, VID-12, VID-17, VID-18, AUD-02, AUD-03, AUD-05, AUD-08, AUD-12, AUD-17, SUB-01, SUB-02, SUB-03, SUB-07, SUB-09, SUB-11, CHP-02, CHP-04 |
| Missing-feasible (MF), this phase | 48 | SUM-04; DIM-04, DIM-07 (8K), DIM-08, DIM-10 (auto), DIM-12, DIM-13; FIL-04 (bob), FIL-05, FIL-06, FIL-07, FIL-08, FIL-09, FIL-10, FIL-12; VID-04, VID-07, VID-08, VID-12, VID-14, VID-15; AUD-01, AUD-02, AUD-04, AUD-06, AUD-09, AUD-11, AUD-13, AUD-15, AUD-16; SUB-01, SUB-02, SUB-04, SUB-05, SUB-10, SUB-13; CHP-01, CHP-02, CHP-03, CHP-04; TAG-01…TAG-08 |
| Missing-feasible, deferred | 6 | DIM-07 (custom max size), DIM-10 (custom PAR), DIM-11, VID-11, VID-19, SUB-12 |
| Not feasible (NF) | 14 (+3 partial) | SUM-02, SUM-06, FIL-01, FIL-11, VID-02, VID-05, VID-13, VID-16, AUD-07, AUD-10, AUD-14, AUD-18, SUB-06, SUB-08; partial: FIL-03 (Yadif/Bwdif/Decomb as distinct algorithms), FIL-04 (EEDI2), VID-17 (free-form x264 options) |

## Phase scope (priority order, used as the plan spec)

1. **Inline tabs (HBP-02):** one selected video → the workspace shows a tab bar Summary · Dimensions · Filters · Video · Audio · Subtitles · Chapters · Tags (+ Trim/Preview inside Summary or Dimensions) with every PH item, in the dark theme. Multi or no selection keeps the "apply to all" inspector with a clear way into the tabs.
2. **Video (HBP-03):** VID-07 rates, VID-08 framerate mode, VID-12 encoder speed, VID-14 profile, VID-15 level, VID-04 ProRes LT/Proxy.
3. **Audio (HBP-04):** AUD-01 per-track list, AUD-02 languages, AUD-04 HE-AAC, AUD-06 auto passthru + fallback, AUD-09 7.1, AUD-11 sample rate, AUD-13 gain, AUD-15 names, AUD-16.
4. **Subtitles / chapters / tags (HBP-04):** SUB-01/02/04/05/10/13, CHP-01/02/03/04, TAG-01…08.
5. **Dimensions / filters (HBP-03):** DIM-04 auto crop, DIM-07 8K, DIM-08 upscaling, DIM-10 anamorphic auto, DIM-12/13 padding, FIL-04 bob, FIL-05/06/07 denoise, FIL-08 chroma smooth, FIL-09/10 sharpen, FIL-12 colorspace, SUM-04 align A/V.
6. **Preset import (HBP-05):** map every new key: `VideoFramerateMode`, `VideoPreset`, `VideoProfile`, `VideoLevel`, `AudioList[*]` (`AudioSamplerate`, `AudioTrackGainSlider`, `AudioTrackName`), `AudioCopyMask`/`AudioAllow*Pass`, `AudioEncoderFallback`, `AudioLanguageList`, `AudioSecondaryEncoderMode`, `SubtitleLanguageList`, `ChapterMarkers`, `MetadataPassthrough`, `AlignAVStart`, `PictureCropMode` 0/2, `PictureAllowUpscaling`, `PicturePAR`, `PicturePadMode/Color/*`, `PictureDenoiseFilter/Preset/Tune`, `PictureChromaSmoothPreset/Tune`, `PictureSharpenFilter/Preset/Tune`, `PictureColorspacePreset`, `PictureDeinterlacePreset` (bob), `PictureDeblockPreset` (note: NF), `PictureDetelecine` (note: NF).

Backward compatibility: every new field decodes with `decodeIfPresent` and defaults that reproduce today's output, so saved queues and presets (`queue.json`, presets) keep loading and encoding the same.
