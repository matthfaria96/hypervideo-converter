import HyperVideoCore
import SwiftUI

struct VideoSettingsTab: View {
    let info: MediaInfo
    @Binding var settings: EncodeSettings

    private var isPassthrough: Bool { settings.videoCodec == .passthrough }

    var body: some View {
        VStack(spacing: 12) {
            encoderSection
            framerateSection
            if settings.videoCodec.supportsRateControl {
                QualitySection(settings: $settings)
                optionsSection
            }
        }
        .onChange(of: settings.videoCodec) { _, codec in
            settings.videoOptions.profile = settings.videoOptions.profile.resolved(for: codec)
            if codec != .h264 { settings.videoOptions.level = .auto }
        }
    }

    private var encoderSection: some View {
        SettingsSection(title: "Encoder", symbol: "cpu") {
            SettingRow(title: "Video encoder") {
                Picker("Video encoder", selection: $settings.videoCodec) {
                    ForEach(VideoCodec.allCases) { Text(localizing: $0.displayName).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            if info.dynamicRange != .sdr && !settings.videoCodec.isTenBit && !isPassthrough {
                Label("This \(info.dynamicRange.rawValue) source will be converted to SDR. Choose HEVC 10-bit or ProRes to keep HDR.",
                      systemImage: "sun.max.trianglebadge.exclamationmark")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var framerateSection: some View {
        SettingsSection(title: "Framerate", symbol: "speedometer") {
            SettingRow(title: "Framerate (FPS)", help: "Same as Source keeps the motion as it was") {
                Picker("Framerate (FPS)", selection: $settings.frameRate) {
                    ForEach(FrameRate.allCases) { Text(localizing: $0.displayName).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            SettingRow(title: "Mode", help: "Peak never goes above the chosen rate; Variable keeps the source's timing") {
                Picker("Mode", selection: $settings.videoOptions.frameRateMode) {
                    ForEach(FrameRateMode.allCases) { Text(localizing: $0.displayName).tag($0) }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }
            .disabled(isPassthrough)
        }
    }

    private var optionsSection: some View {
        SettingsSection(title: "Encoder Options", symbol: "slider.horizontal.3") {
            SettingRow(title: "Speed", help: "Faster encodes at slightly lower efficiency") {
                Picker("Speed", selection: $settings.videoOptions.speed) {
                    ForEach(EncoderSpeed.allCases) { Text(localizing: $0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            SettingRow(title: "Profile") {
                Picker("Profile", selection: $settings.videoOptions.profile) {
                    ForEach(VideoProfile.options(for: settings.videoCodec)) { Text(localizing: $0.displayName).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            if settings.videoCodec == .h264 {
                SettingRow(title: "Level") {
                    Picker("Level", selection: $settings.videoOptions.level) {
                        ForEach(VideoLevel.options(for: settings.videoCodec)) { Text(localizing: $0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            SettingRow(title: "Keyframe interval") {
                Stepper(value: $settings.keyframeIntervalSeconds, in: 0.5...10, step: 0.5) {
                    Text("\(settings.keyframeIntervalSeconds.formatted()) s").monospacedDigit()
                }
            }
            SettingRow(title: "B-frames", help: "Better compression; disable for some editors") {
                Toggle("B-frames", isOn: $settings.allowBFrames).labelsHidden().toggleStyle(.switch)
            }
        }
    }
}
