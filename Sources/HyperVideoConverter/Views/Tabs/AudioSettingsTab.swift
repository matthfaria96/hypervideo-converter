import HyperVideoCore
import SwiftUI

/// Audio tab: selection behavior, main encoding, explicit track list, extra version.
struct AudioSettingsTab: View {
    let info: MediaInfo
    @Binding var settings: EncodeSettings

    /// The main version as one encoding, so it shares the fields view with tracks.
    private var mainEncoding: Binding<AudioEncoding> {
        Binding(
            get: {
                AudioEncoding(
                    codec: settings.audioCodec, mixdown: settings.audioMixdown, bitrateKbps: settings.audioBitrateKbps,
                    sampleRate: settings.audioOptions.sampleRate, gainDb: settings.audioOptions.gainDb,
                    trackName: settings.audioOptions.trackName)
            },
            set: { value in
                settings.audioCodec = value.codec
                settings.audioMixdown = value.mixdown
                settings.audioBitrateKbps = value.bitrateKbps
                settings.audioOptions.sampleRate = value.sampleRate
                settings.audioOptions.gainDb = value.gainDb
                settings.audioOptions.trackName = value.trackName
            }
        )
    }

    var body: some View {
        VStack(spacing: 16) {
            AudioBehaviorSection(settings: $settings)
            if settings.audioTracks != .none && settings.audioOptions.tracks.isEmpty {
                SettingsSection(title: "Encoding", symbol: "waveform") {
                    AudioEncodingFields(encoding: mainEncoding, codecs: AudioCodec.allCases)
                }
            }
            tracksSection
            if settings.audioCodec != .none {
                ExtraVersionSection(settings: $settings, bitrates: audioBitrateChoices)
            }
            sourceTracksSection
        }
    }

    private var tracksSection: some View {
        SettingsSection(title: "Tracks", symbol: "list.number") {
            if settings.audioOptions.tracks.isEmpty {
                Text("Tracks follow the selection behavior above.").foregroundStyle(.secondary)
            }
            ForEach(Array(settings.audioOptions.tracks.enumerated()), id: \.element.id) { index, track in
                AudioTrackCard(setting: trackBinding(track), number: index + 1, sources: info.audioTracks) {
                    settings = settings.removingAudioTrack(track.id)
                }
            }
            HStack {
                Button("Add Track", systemImage: "plus") { settings = settings.addingAudioTrack(from: info) }
                Button("Add All Tracks", systemImage: "plus.square.on.square") {
                    settings = settings.addingAllAudioTracks(from: info)
                }
                Button("Reload from Behavior", systemImage: "arrow.counterclockwise") {
                    settings = settings.resettingAudioTracks()
                }
                .disabled(settings.audioOptions.tracks.isEmpty)
            }
            .buttonStyle(.subtle)
            .disabled(info.audioTracks.isEmpty)
        }
    }

    /// Looks the track up by id on every access, so a field committing after its card
    /// was removed can't write through a stale array index.
    private func trackBinding(_ track: AudioTrackSetting) -> Binding<AudioTrackSetting> {
        Binding(
            get: { settings.audioOptions.tracks.first { $0.id == track.id } ?? track },
            set: { settings = settings.updatingAudioTrack($0) }
        )
    }

    private var sourceTracksSection: some View {
        SettingsSection(title: "Source Tracks", symbol: "list.bullet") {
            if info.audioTracks.isEmpty {
                Text("This source has no audio.").foregroundStyle(.secondary)
            }
            ForEach(Array(info.audioTracks.enumerated()), id: \.element.id) { index, track in
                HStack {
                    Text("Track \(index + 1)").fontWeight(.medium)
                    Text(verbatim: "\(track.codec) · \(String(localized: String.LocalizationValue(track.channelDescription))) · \(Int(track.sampleRate / 1000)) kHz")
                        .foregroundStyle(.secondary)
                    if let name = track.name { Text(verbatim: name).foregroundStyle(.tertiary).lineLimit(1) }
                    Spacer()
                    if let language = track.language { InfoChip(symbol: "globe", text: language) }
                }
            }
        }
    }
}
