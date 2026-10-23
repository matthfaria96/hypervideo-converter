import HyperVideoCore
import SwiftUI

/// "Output settings": the everyday choices, applied to the selected videos or to all of them.
struct OutputInspector: View {
    @Environment(AppModel.self) private var model

    private var settings: EncodeSettings { model.inspectorSettings }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Output Settings").font(.system(size: 14, weight: .bold)).padding(.bottom, 8)
                ScopeChip().padding(.bottom, 12)
                // The way into every HandBrake setting stays in view, above the quick fields.
                AllSettingsHintCard().padding(.bottom, 18)

                FieldLabel(title: "Output Format")
                FormatPicker(settings: settings) { container in model.editTargets { $0 = $0.choosing(container: container) } }
                    .help("The file type, shown as the file's extension (.mp4, .mov…).")
                    .padding(.bottom, 17)

                FieldLabel(title: "Quality Profile")
                ProfileCards(selected: model.inspectorProfile) { model.applyProfile($0) }
                    .padding(.bottom, 8)
                if let personalized = model.inspectorPersonalizedProfile {
                    PersonalizedNote(profile: personalized) { model.applyProfile(personalized) }
                        .padding(.bottom, 8)
                }
                EstimateCard().padding(.top, 4)

                InspectorDivider()
                VideoFields(settings: settings) { change in model.editTargets(change) }
                InspectorDivider()
                InspectorToggles(settings: settings) { change in model.editTargets(change) }

                if !settings.validationIssues.isEmpty {
                    StatusBanner(messages: settings.validationIssues.map { String(localized: String.LocalizationValue($0)) })
                        .padding(.top, 12)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 22)
        }
        .background(Theme.inspector)
    }
}

struct FieldLabel: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?

    var body: some View {
        HStack {
            Text(title).font(.system(size: 11, weight: .semibold))
            Spacer()
            if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(Theme.muted) }
        }
        .padding(.bottom, 8)
    }
}

struct InspectorDivider: View {
    var body: some View {
        Color(hex: 0x39393E).frame(height: 1).padding(.vertical, 18)
    }
}

private struct FormatPicker: View {
    let settings: EncodeSettings
    let choose: @MainActor @Sendable (ContainerFormat) -> Void

    var body: some View {
        MenuField(label: "Output Format", selection: settings.container, options: ContainerFormat.allCases,
                  title: Self.title, choose: choose)
    }

    static func title(_ format: ContainerFormat) -> LocalizedStringKey {
        switch format {
        case .mp4: "MP4 — most compatible"
        case .mov: "MOV — Apple / editing"
        case .mkv: "MKV — multiple tracks"
        case .m4v: "M4V — Apple devices"
        }
    }
}
