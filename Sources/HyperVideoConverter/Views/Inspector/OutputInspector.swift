import HyperVideoCore
import SwiftUI

/// "Output settings": the everyday choices, applied to the selected videos or to all of them.
/// A fixed header (title, scope, the way into every setting) over the scrolling fields,
/// laid out like the single-video panel so switching between them doesn't jump.
struct OutputInspector: View {
    @Environment(AppModel.self) private var model

    private var settings: EncodeSettings { model.inspectorSettings }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    group {
                        FieldLabel(title: "Output Format", symbol: "shippingbox")
                        FormatPicker(settings: settings) { container in model.editTargets { $0 = $0.choosing(container: container) } }
                            .help("The file type, shown as the file's extension (.mp4, .mov…).")
                    }

                    group {
                        FieldLabel(title: "Quality Profile", symbol: "dial.medium")
                        ProfileCards(selected: model.inspectorProfile) { model.applyProfile($0) }
                        if let personalized = model.inspectorPersonalizedProfile {
                            PersonalizedNote(profile: personalized) { model.applyProfile(personalized) }
                                .motionTransition(.pop)
                        }
                        EstimateCard()
                    }
                    .motion(value: model.inspectorPersonalizedProfile)

                    group { VideoFields(settings: settings) { change in model.editTargets(change) } }
                    group { InspectorToggles(settings: settings) { change in model.editTargets(change) } }

                    if !settings.validationIssues.isEmpty {
                        StatusBanner(messages: settings.validationIssues.map { String(localized: String.LocalizationValue($0)) })
                            .motionTransition(.pop)
                    }
                }
                .padding(Spacing.l)
                .motion(value: settings.validationIssues)
            }
            .compatSoftScrollEdges()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("Output Settings").font(.title3.weight(.semibold))
                Spacer()
                if !model.sources.isEmpty {
                    Button { model.showFirstVideoSettings() } label: {
                        Label("All Settings", systemImage: "slider.horizontal.3")
                    }
                    .compatGlassButtonStyle()
                    .controlSize(.small)
                    .help("Select one video to see every setting: dimensions, filters, video, audio, subtitles, chapters and tags.")
                    .motionTransition(.pop)
                }
            }
            ScopeChip()
        }
        .padding(Spacing.l)
        .motion(value: model.sources.isEmpty)
    }

    /// One card per group of fields.
    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) { content() }
            .padding(Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
    }
}

struct FieldLabel: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?
    var symbol: String?

    var body: some View {
        HStack(spacing: Spacing.s) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 18)
            }
            Text(title).font(.headline)
            Spacer()
            if let detail { Text(detail).font(.footnote).foregroundStyle(.secondary) }
        }
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
