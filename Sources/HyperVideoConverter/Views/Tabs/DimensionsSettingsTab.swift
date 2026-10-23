import AppKit
import HyperVideoCore
import SwiftUI

struct DimensionsSettingsTab: View {
    let info: MediaInfo
    @Binding var settings: EncodeSettings
    @State private var detectedCrop: Crop?

    private var padding: Binding<Padding> { $settings.pictureOptions.padding }

    var body: some View {
        VStack(spacing: 12) {
            if settings.videoCodec == .passthrough {
                StatusBanner(messages: [String(localized: "Passthrough copies the video as is. Choose an encoder in Video to change its size.")])
            }
            CropSection(info: info, settings: $settings, detectedCrop: $detectedCrop)
            resolutionSection
            bordersSection
            finalSection
        }
    }

    private var resolutionSection: some View {
        SettingsSection(title: "Resolution & Scaling", symbol: "aspectratio") {
            SettingRow(title: "Resolution limit", help: "Keeps the aspect ratio") {
                Picker("Resolution limit", selection: $settings.maxResolution) {
                    ForEach(MaxResolution.allCases) { Text(localizing: $0.displayName).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            SettingRow(title: "Allow upscaling", help: "Enlarges smaller videos up to the limit") {
                Toggle("Allow upscaling", isOn: $settings.pictureOptions.allowUpscaling)
                    .labelsHidden().toggleStyle(.switch)
            }
            SettingRow(title: "Anamorphic", help: "Automatic keeps the source's pixel shape") {
                Picker("Anamorphic", selection: $settings.pictureOptions.anamorphic) {
                    ForEach(Anamorphic.allCases) { Text(localizing: $0.displayName).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    private var bordersSection: some View {
        SettingsSection(title: "Borders", symbol: "rectangle.dashed") {
            SettingRow(title: "Fill") {
                Picker("Fill", selection: padding.mode) {
                    ForEach(PaddingMode.allCases) { Text(localizing: $0.displayName).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            if padding.wrappedValue.mode != .none {
                SettingRow(title: "Color") {
                    HStack {
                        Picker("Color", selection: padding.color) {
                            ForEach(PadColor.allCases) { Text(localizing: $0.displayName).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        if padding.wrappedValue.color == .custom {
                            ColorPicker("Color", selection: colorBinding, supportsOpacity: false).labelsHidden()
                        }
                    }
                }
            }
        }
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: {
                let pad = settings.pictureOptions.padding
                return Color(.sRGB, red: pad.red, green: pad.green, blue: pad.blue)
            },
            set: { color in
                guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                settings.pictureOptions.padding.customHex = PadColorHex.hex(
                    red: Double(rgb.redComponent), green: Double(rgb.greenComponent), blue: Double(rgb.blueComponent))
            }
        )
    }

    private var finalSection: some View {
        let final = FinalDimensions.compute(info: info, settings: settings, detectedCrop: detectedCrop)
        return SettingsSection(title: "Final Dimensions", symbol: "ruler") {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                dimensionRow("Source", info.displaySize)
                dimensionRow("Storage", final?.storage)
                dimensionRow("Display", final?.display)
            }
        }
    }

    private func dimensionRow(_ title: LocalizedStringKey, _ size: CGSize?) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(size.map { Format.size($0) } ?? "–").monospacedDigit()
        }
    }
}
