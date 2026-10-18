import HyperVideoCore
import SwiftUI

// MARK: Dimensions

struct DimensionsTab: View {
    let info: MediaInfo
    @Binding var settings: EncodeSettings

    var body: some View {
        VStack(spacing: 16) {
            if settings.videoCodec == .passthrough {
                StatusBanner(messages: ["Passthrough copies the video as is. Choose an encoder in Video to change its size."])
            }
            GlassSection(title: "Size", symbol: "aspectratio") {
                SettingRow(title: "Maximum resolution", help: "Never upscales; keeps the aspect ratio") {
                    Picker("Maximum resolution", selection: $settings.maxResolution) {
                        ForEach(MaxResolution.allCases) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            GlassSection(title: "Orientation", symbol: "rotate.right") {
                SettingRow(title: "Rotate") {
                    Picker("Rotate", selection: $settings.rotation) {
                        ForEach(Rotation.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                SettingRow(title: "Flip horizontally") {
                    Toggle("Flip", isOn: $settings.flipHorizontal).labelsHidden().toggleStyle(.switch)
                }
            }
            GlassSection(title: "Crop", symbol: "crop") {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                    GridRow {
                        cropField("Top", \.top)
                        cropField("Bottom", \.bottom)
                    }
                    GridRow {
                        cropField("Left", \.left)
                        cropField("Right", \.right)
                    }
                }
                HStack {
                    Button("Reset", systemImage: "arrow.counterclockwise") { settings.crop = .zero }
                        .buttonStyle(.glass)
                        .disabled(settings.crop.isZero)
                    if let size = info.displaySize, size.width > size.height {
                        Button("Crop to 2.39:1", systemImage: "rectangle.ratio.16.to.9") {
                            let bar = max(0, Int((size.height - size.width / 2.39) / 2))
                            settings.crop = Crop(top: bar, bottom: bar)
                        }
                        .buttonStyle(.glass)
                    }
                }
            }
        }
    }

    private func cropField(_ title: String, _ edge: WritableKeyPath<Crop, Int>) -> some View {
        HStack {
            Text(title).frame(width: 56, alignment: .leading)
            TextField(title, value: $settings.crop[dynamicMember: edge], format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
            Stepper(title, value: $settings.crop[dynamicMember: edge], in: 0...4_000, step: 2).labelsHidden()
            Text("px").foregroundStyle(.secondary)
        }
    }
}

// MARK: Audio

struct AudioTab: View {
    let info: MediaInfo
    @Binding var settings: EncodeSettings

    private let bitrates = [64, 96, 128, 160, 192, 256, 320, 384, 448, 640]

    var body: some View {
        VStack(spacing: 16) {
            GlassSection(title: "Encoding", symbol: "waveform") {
                SettingRow(title: "Codec") {
                    Picker("Codec", selection: $settings.audioCodec) {
                        ForEach(AudioCodec.allCases) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                if settings.audioCodec != .none {
                    SettingRow(title: "Tracks") {
                        Picker("Tracks", selection: $settings.audioTracks) {
                            ForEach(AudioTrackSelection.allCases) { Text($0.displayName).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                if settings.audioCodec == .aac || settings.audioCodec == .alac {
                    SettingRow(title: "Mixdown", help: "Falls back automatically if the source has fewer channels") {
                        Picker("Mixdown", selection: $settings.audioMixdown) {
                            ForEach(AudioMixdown.allCases) { Text($0.displayName).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                if settings.audioCodec == .aac {
                    SettingRow(title: "Bitrate") {
                        Picker("Bitrate", selection: $settings.audioBitrateKbps) {
                            ForEach(bitrates, id: \.self) { Text("\($0) kbit/s").tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            }

            if settings.audioCodec != .none {
                ExtraAudioSection(settings: $settings, bitrates: bitrates)
            }

            GlassSection(title: "Source Tracks", symbol: "list.number") {
                if info.audioTracks.isEmpty {
                    Text("This source has no audio.").foregroundStyle(.secondary)
                }
                ForEach(Array(info.audioTracks.enumerated()), id: \.element.id) { index, track in
                    HStack {
                        Image(systemName: included(index) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(included(index) ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                        Text("Track \(index + 1)").fontWeight(.medium)
                        Text("\(track.codec) · \(track.channelDescription) · \(Int(track.sampleRate / 1000)) kHz")
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let language = track.language { InfoChip(symbol: "globe", text: language) }
                    }
                }
            }
        }
    }

    private func included(_ index: Int) -> Bool {
        settings.audioCodec != .none && (settings.audioTracks == .all || index == 0)
    }
}

/// A second version of every kept track, e.g. AAC stereo next to surround passthrough.
private struct ExtraAudioSection: View {
    @Binding var settings: EncodeSettings
    let bitrates: [Int]

    private var isOn: Binding<Bool> {
        Binding(
            get: { settings.extraAudio != nil },
            set: { on in
                settings.extraAudio = on ? AudioEncoding(codec: settings.audioCodec == .aac ? .passthrough : .aac,
                                                         mixdown: .stereo, bitrateKbps: 160) : nil
            }
        )
    }

    private var extra: Binding<AudioEncoding> {
        Binding(
            get: { settings.extraAudio ?? AudioEncoding(codec: .aac, mixdown: .stereo, bitrateKbps: 160) },
            set: { settings.extraAudio = $0 }
        )
    }

    var body: some View {
        GlassSection(title: "Extra Version", symbol: "square.stack") {
            SettingRow(title: "Add a second version", help: "Each kept track is also written this way; players pick one") {
                Toggle("Add a second version", isOn: isOn).labelsHidden().toggleStyle(.switch)
            }
            if settings.extraAudio != nil {
                SettingRow(title: "Codec") {
                    Picker("Codec", selection: extra.codec) {
                        ForEach(AudioCodec.allCases.filter { $0 != .none }) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                if extra.wrappedValue.codec == .aac || extra.wrappedValue.codec == .alac {
                    SettingRow(title: "Mixdown") {
                        Picker("Mixdown", selection: extra.mixdown) {
                            ForEach(AudioMixdown.allCases) { Text($0.displayName).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                if extra.wrappedValue.codec == .aac {
                    SettingRow(title: "Bitrate") {
                        Picker("Bitrate", selection: extra.bitrateKbps) {
                            ForEach(bitrates, id: \.self) { Text("\($0) kbit/s").tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            }
        }
    }
}
