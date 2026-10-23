import HyperVideoCore
import SwiftUI

struct FiltersSettingsTab: View {
    let info: MediaInfo
    @Binding var settings: EncodeSettings

    private var filters: Binding<VideoFilters> { $settings.filters }

    var body: some View {
        VStack(spacing: 12) {
            if settings.videoCodec == .passthrough {
                StatusBanner(messages: ["Filters need the video to be re-encoded. Choose an encoder in Video."])
            }
            SettingsSection(title: "Filters", symbol: "camera.filters") {
                deinterlaceRows
                denoiseRows
                chromaRows
                sharpenRows
                SettingRow(title: "Colorspace") {
                    menu("Colorspace", ColorspaceTarget.allCases, filters.colorspace)
                }
                SettingRow(title: "Grayscale") {
                    Toggle("Grayscale", isOn: filters.grayscale).labelsHidden().toggleStyle(.switch)
                }
                Text("Detelecine and Deblock aren't available on macOS's video engine.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            .disabled(settings.videoCodec == .passthrough)
        }
    }

    private var deinterlaceRows: some View {
        Group {
            SettingRow(
                title: "Deinterlace",
                help: info.isInterlaced
                    ? "This source is interlaced: removes the comb-like lines of TV and camcorder video"
                    : "Removes comb-like lines; Automatic acts only on interlaced sources"
            ) {
                menu("Deinterlace", DeinterlaceMode.allCases, filters.deinterlace)
            }
            if settings.filters.deinterlace != .off {
                SettingRow(title: "Method") {
                    menu("Method", DeinterlaceMethod.allCases, filters.deinterlaceMethod)
                }
            }
        }
    }

    private var denoiseRows: some View {
        Group {
            SettingRow(title: "Denoise", help: "Smooths grain and compression noise") {
                menu("Denoise", DenoiseChoice.allCases, Binding(
                    get: { settings.filters.denoiseChoice },
                    set: { settings.filters = settings.filters.choosingDenoise($0) }))
            }
            if settings.filters.denoise != .off {
                SettingRow(title: "Strength") {
                    menu("Strength", activeStrengths, filters.denoise)
                }
                SettingRow(title: "Tune") {
                    menu("Tune", DenoiseTune.allCases, filters.denoiseTune)
                }
            }
        }
    }

    private var chromaRows: some View {
        Group {
            SettingRow(title: "Chroma smooth", help: "Cleans up color fringing") {
                menu("Chroma smooth", FilterStrength.allCases, filters.chromaSmooth)
            }
            if settings.filters.chromaSmooth != .off {
                SettingRow(title: "Tune") {
                    menu("Tune", ChromaSmoothTune.allCases, filters.chromaSmoothTune)
                }
            }
        }
    }

    private var sharpenRows: some View {
        Group {
            SettingRow(title: "Sharpen", help: "Crisper edges; best kept light") {
                menu("Sharpen", SharpenChoice.allCases, Binding(
                    get: { settings.filters.sharpenChoice },
                    set: { settings.filters = settings.filters.choosingSharpen($0) }))
            }
            if settings.filters.sharpen != .off {
                SettingRow(title: "Strength") {
                    menu("Strength", activeStrengths, filters.sharpen)
                }
                SettingRow(title: "Tune") {
                    menu("Tune", SharpenTune.options(for: settings.filters.sharpenFilter), filters.sharpenTune)
                }
            }
        }
    }

    private var activeStrengths: [FilterStrength] { FilterStrength.allCases.filter { $0 != .off } }

    private func menu<Value: Hashable & Identifiable>(
        _ title: LocalizedStringKey, _ options: [Value], _ selection: Binding<Value>
    ) -> some View where Value: DisplayNamed {
        Picker(title, selection: selection) {
            ForEach(options) { Text(localizing: $0.displayName).tag($0) }
        }
        .labelsHidden()
        .fixedSize()
    }
}

/// Anything with a display name the menus can show.
protocol DisplayNamed {
    var displayName: String { get }
}

extension DeinterlaceMode: DisplayNamed {}
extension DeinterlaceMethod: DisplayNamed {}
extension DenoiseTune: DisplayNamed {}
extension ChromaSmoothTune: DisplayNamed {}
extension SharpenTune: DisplayNamed {}
extension ColorspaceTarget: DisplayNamed {}
extension FilterStrength: DisplayNamed {}
extension DenoiseChoice: DisplayNamed {}
extension SharpenChoice: DisplayNamed {}
