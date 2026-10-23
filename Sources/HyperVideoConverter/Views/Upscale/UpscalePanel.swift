import HyperVideoCore
import SwiftUI

/// The settings column in AI Upscale mode: what the result will be (size, weight, time)
/// first, then the three choices that change it.
struct UpscalePanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    if !AppModel.upscaleAvailable {
                        StatusBanner(messages: [String(localized: "The AI engine isn't included in this build. Run Scripts/fetch-upscayl.sh and build again.")])
                    }
                    UpscalePredictionCard(estimate: model.upscaleEstimate)
                    UpscaleModelPicker(selection: $model.upscaleSettings.model)
                    scaleSection
                    weightSection
                    credits
                }
                .padding(Spacing.l)
                .motion(value: model.upscaleSettings)
            }
            .compatSoftScrollEdges()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Label("AI Upscale", systemImage: "sparkles")
                .font(.title3.weight(.semibold))
                .symbolRenderingMode(.multicolor)
            Text(verbatim: scopeText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.l)
    }

    private var scopeText: String {
        let count = model.upscaleTargets.count
        if model.sources.isEmpty { return String(localized: "Enlarges videos with Real-ESRGAN. Add videos to see the result before starting.") }
        if model.inspectsSelection {
            return count == 1 ? String(localized: "For the selected video") : String(localized: "For the \(count) selected videos")
        }
        return count == 1 ? String(localized: "For the video in the list") : String(localized: "For all \(count) videos in the list")
    }

    private var scaleSection: some View {
        @Bindable var model = model
        return SettingsSection(title: "Enlargement", symbol: "arrow.up.left.and.arrow.down.right") {
            Picker("Scale", selection: $model.upscaleSettings.scale) {
                ForEach(UpscaleScale.allCases) { Text(verbatim: $0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            SwitchRow(title: "Limit to 4K", detail: "Never larger than 3840 × 2160. Bigger files are hard to play and share.",
                      isOn: model.upscaleSettings.limitTo4K) { model.upscaleSettings.limitTo4K = $0 }
        }
    }

    private var weightSection: some View {
        @Bindable var model = model
        return SettingsSection(title: "File Weight", symbol: "scalemass") {
            Picker("File weight", selection: $model.upscaleSettings.weight) {
                ForEach(UpscaleWeight.allCases) { Text(localizing: $0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(weightHelp)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            SettingRow(title: "Codec", help: "HEVC makes files about 40% smaller; H.264 plays on older devices.") {
                Picker("Codec", selection: $model.upscaleSettings.codec) {
                    ForEach(UpscaleCodec.allCases) { Text(verbatim: $0.displayName).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    private var weightHelp: LocalizedStringKey {
        switch model.upscaleSettings.weight {
        case .compact: "Smallest file. Fine detail is softened a little."
        case .balanced: "Keeps the upscaled detail at a reasonable size. Recommended."
        case .high: "Keeps every detail the model adds. Much bigger files."
        }
    }

    private var credits: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Label("The audio is copied as is. Subtitles, chapters and the settings of the other tabs aren't applied when upscaling.",
                  systemImage: "info.circle")
            HStack(spacing: Spacing.xs) {
                Text("Engine: Upscayl (AGPL-3.0) with Real-ESRGAN, on the Mac's GPU.")
                Link("Source code", destination: URL(string: "https://github.com/upscayl/upscayl-ncnn")!)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}
