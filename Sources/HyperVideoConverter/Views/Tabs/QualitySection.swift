import HyperVideoCore
import SwiftUI

/// Constant quality or average bitrate.
struct QualitySection: View {
    @Binding var settings: EncodeSettings
    @State private var memory = RateControlMemory()

    private var isQuality: Binding<Bool> {
        Binding(
            get: { if case .quality = settings.rateControl { true } else { false } },
            set: { settings.rateControl = memory.switching(toQuality: $0, from: settings.rateControl) }
        )
    }

    private var quality: Binding<Double> {
        Binding(
            get: { if case .quality(let q) = settings.rateControl { q } else { RateControlMemory.defaultQuality } },
            set: { settings.rateControl = .quality($0) }
        )
    }

    private var bitrate: Binding<Int> {
        Binding(
            get: { if case .averageBitrate(let kbps) = settings.rateControl { kbps } else { RateControlMemory.defaultBitrateKbps } },
            set: { settings.rateControl = .averageBitrate(max(100, $0)) }
        )
    }

    var body: some View {
        SettingsSection(title: "Quality", symbol: "dial.medium") {
            Picker("Mode", selection: isQuality) {
                Text("Constant Quality").tag(true)
                Text("Average Bitrate").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            if isQuality.wrappedValue {
                qualitySlider
            } else {
                SettingRow(title: "Average bitrate") {
                    HStack {
                        TextField("kbit/s", value: bitrate, format: .number)
                            .frame(width: 100)
                            .textFieldStyle(.roundedBorder)
                        Text("kbit/s").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var qualitySlider: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Self.describe(quality.wrappedValue)).fontWeight(.semibold)
                Spacer()
                Text("\(Int(quality.wrappedValue * 100))").monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: quality, in: 0.2...1) {
                Text("Quality")
            } minimumValueLabel: {
                Text("Smaller").font(.caption)
            } maximumValueLabel: {
                Text("Better").font(.caption)
            }
            .labelsHidden()
        }
    }

    static func describe(_ quality: Double) -> LocalizedStringKey {
        switch quality {
        case ..<0.4: "Compact"
        case ..<0.58: "Balanced"
        case ..<0.75: "High Quality"
        case ..<0.9: "Very High Quality"
        default: "Near Lossless"
        }
    }
}
