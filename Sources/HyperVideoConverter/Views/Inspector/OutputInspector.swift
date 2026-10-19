import HyperVideoCore
import SwiftUI

/// "Output settings": the everyday choices, applied to the selected videos or to all of them.
struct OutputInspector: View {
    @Environment(AppModel.self) private var model

    private var settings: EncodeSettings { model.inspectorSettings }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Output Settings").font(.system(size: 14, weight: .bold)).padding(.bottom, 5)
                Text(verbatim: scopeText)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 20)

                FieldLabel(title: "Output Format", detail: "File type")
                FormatPicker(settings: settings) { container in model.editTargets { $0 = $0.choosing(container: container) } }
                    .padding(.bottom, 17)

                FieldLabel(title: "Quality Profile", detail: "Recommended")
                ProfileCards(selected: model.inspectorProfile) { model.applyProfile($0) }
                    .padding(.bottom, 17)

                InspectorDivider()
                VideoFields(settings: settings) { change in model.editTargets(change) }
                InspectorDivider()
                InspectorToggles(settings: settings) { change in model.editTargets(change) }

                if !settings.validationIssues.isEmpty {
                    StatusBanner(messages: settings.validationIssues.map { String(localized: String.LocalizationValue($0)) })
                        .padding(.top, 12)
                }
                EstimateCard().padding(.top, 17)
                advanced.padding(.top, 14)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 22)
        }
        .background(Theme.inspector)
    }

    private var scopeText: String {
        let targets = model.inspectorTargetIDs.count
        if model.sources.isEmpty { return String(localized: "Pick a ready-made profile or fine-tune the details. These settings go to the videos you add next.") }
        if model.inspectsSelection {
            return targets == 1 ? String(localized: "Changes apply to the selected video.")
                : String(localized: "Changes apply to the \(targets) selected videos.")
        }
        if targets == 1 { return String(localized: "Changes apply to the video in the list.") }
        return String(localized: "Changes apply to all \(targets) videos in the list. Select rows to change only some.")
    }

    private var advanced: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                model.ui.advancedSourceID = model.selectedSource?.id
            } label: {
                Label("Advanced Settings…", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.subtle)
            .disabled(model.selectedSource?.info == nil)
            Text("Trim, crop, filters, audio tracks, subtitles and chapters for one video.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
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
