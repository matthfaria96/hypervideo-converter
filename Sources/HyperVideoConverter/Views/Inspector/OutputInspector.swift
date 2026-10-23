import HyperVideoCore
import SwiftUI

/// Compress mode's panel: shrink by a quality level or to a target size, with the
/// result's size up front; format and fine video choices below. Built from the same
/// sections and rows as every other panel.
struct OutputInspector: View {
    @Environment(AppModel.self) private var model

    private var settings: EncodeSettings { model.inspectorSettings }
    private var edit: SettingsEdit { { change in model.editTargets(change) } }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader { CompressGoalPicker() }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    if model.compressTargetMB != nil {
                        SettingsSection(title: "Target Size", symbol: "scalemass") { TargetSizeFields() }
                            .motionTransition(.content)
                    } else {
                        qualitySection.motionTransition(.content)
                    }
                    EstimateCard(estimate: model.compressEstimate)
                    outputSection
                    // A target size decides codec, bitrate and resolution itself.
                    if model.compressTargetMB == nil {
                        SettingsSection(title: "Video", symbol: "film") { VideoFields(settings: settings, edit: edit) }
                    }
                    if !settings.validationIssues.isEmpty {
                        StatusBanner(messages: settings.validationIssues.map { String(localized: String.LocalizationValue($0)) })
                            .motionTransition(.pop)
                    }
                }
                .padding(Spacing.l)
                .motion(value: settings.validationIssues)
                .motion(value: model.compressTargetMB == nil)
            }
            .compatSoftScrollEdges()
        }
    }

    private var qualitySection: some View {
        SettingsSection(title: "Quality Profile", symbol: "dial.medium") {
            ProfileCards(selected: model.inspectorProfile) { model.applyProfile($0) }
            if let personalized = model.inspectorPersonalizedProfile {
                PersonalizedNote(profile: personalized) { model.applyProfile(personalized) }
                    .motionTransition(.pop)
            }
        }
        .motion(value: model.inspectorPersonalizedProfile)
    }

    private var outputSection: some View {
        SettingsSection(title: "Output", symbol: "shippingbox") {
            SettingRow(title: "Format", help: "The file type, shown as the file's extension (.mp4, .mov…).") {
                Picker("Format", selection: Binding(
                    get: { settings.container },
                    set: { container in model.editTargets { $0 = $0.choosing(container: container) } })) {
                    ForEach(ContainerFormat.allCases.filter { !$0.isAudioOnly }) { Text(localizing: $0.displayName).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            InspectorToggles(settings: settings, edit: edit)
        }
    }
}
