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

    private var header: some View { PanelHeader() }

    private var scaleSection: some View {
        @Bindable var model = model
        return SettingsSection(title: "Enlargement", symbol: "arrow.up.left.and.arrow.down.right") {
            Picker("Scale", selection: $model.upscaleSettings.scale) {
                ForEach(UpscaleScale.allCases) { Text(verbatim: $0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            SettingRow(title: "Limit to 4K", help: "Never larger than 3840 × 2160. Bigger files are hard to play and share.") {
                Toggle("Limit to 4K", isOn: $model.upscaleSettings.limitTo4K).labelsHidden().toggleStyle(.switch)
            }
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
            // Text and link on one baseline, wrapping together; the icon column lines up with the note above.
            Label {
                (Text("Engine: Upscayl (AGPL-3.0) with Real-ESRGAN, on the Mac's GPU.") + Text(verbatim: " ")
                    + Text("[Source code](https://github.com/upscayl/upscayl-ncnn)"))
                    .tint(Theme.accentText)
            } icon: {
                Image(systemName: "cpu")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}
