import HyperVideoCore
import SwiftUI

/// Says, up front, which videos the inspector's changes go to.
struct ScopeChip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: model.inspectsSelection ? "checkmark.circle.fill" : "square.stack.3d.up")
                    .font(.system(size: 11))
                Text(verbatim: title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if model.inspectsSelection {
                    Button {
                        model.selectedIDs = []
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                            .frame(width: 28, height: 22)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help("Stop editing only the selection")
                    .accessibilityLabel(Text("Deselect All"))
                }
            }
            .foregroundStyle(model.inspectsSelection ? Theme.accentLight : Theme.text)
            .padding(.leading, 10)
            .padding(.trailing, model.inspectsSelection ? 0 : 10)
            .padding(.vertical, model.inspectsSelection ? 2 : 6)
            .card(fill: model.inspectsSelection ? Theme.selectedCard : Theme.panelRaised, radius: 8,
                  stroke: model.inspectsSelection ? Color(hex: 0xD9A33A) : Theme.line)
            .accessibilityElement(children: .combine)

            Text(verbatim: detail)
                .font(.system(size: 10))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var title: String {
        let count = model.inspectorTargetIDs.count
        if model.sources.isEmpty { return String(localized: "Editing: next videos added") }
        if model.inspectsSelection {
            if count == 1, let name = model.selectedSource?.name { return String(localized: "Editing: \(name)") }
            return String(localized: "Editing: \(count) videos")
        }
        return count == 1 ? String(localized: "Editing: the video in the list") : String(localized: "Editing: all \(count) videos")
    }

    private var detail: String {
        var lines: [String] = []
        if model.sources.isEmpty {
            lines.append(String(localized: "Pick a profile or fine-tune the details; videos you add get these settings."))
        } else if model.inspectsSelection {
            lines.append(String(localized: "Only the selected videos change. Click ✕ to edit all of them."))
        } else {
            lines.append(String(localized: "Also applies to videos you add next. Select rows to change only some."))
        }
        if !model.activeJobs.isEmpty || model.sources.contains(where: { $0.errorMessage != nil }) {
            lines.append(String(localized: "Videos already in the queue or with errors aren't affected."))
        }
        return lines.joined(separator: " ")
    }
}

/// "Personalized" state of a profile with a link that restores its settings.
struct PersonalizedNote: View {
    let profile: QualityProfile
    let restore: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "slider.horizontal.3").font(.system(size: 10))
            Text("\(Text(localizing: profile.name)) (personalized)")
                .font(.system(size: 10))
            Spacer(minLength: 4)
            Button("Restore") { restore() }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.accentLight)
                .frame(minHeight: 28)
                .contentShape(.rect)
                .help("Go back to this profile's settings")
        }
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, 10)
        .card(fill: Theme.panel, radius: 8)
    }
}
