import HyperVideoCore
import SwiftUI

/// Says, up front, which videos the inspector's changes go to.
struct ScopeChip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs + 2) {
            HStack(spacing: Spacing.s) {
                Image(systemName: model.inspectsSelection ? "checkmark.circle.fill" : "square.stack.3d.up")
                    .foregroundStyle(model.inspectsSelection ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                    .contentTransition(.symbolEffect(.replace))
                Text(verbatim: title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: Spacing.xs)
                if model.inspectsSelection {
                    RowRemoveButton(help: "Stop editing only the selection", label: String(localized: "Deselect All")) {
                        model.selectedIDs = []
                    }
                    .motionTransition(.pop)
                }
            }
            .padding(.leading, Spacing.m)
            .padding(.trailing, model.inspectsSelection ? Spacing.xs : Spacing.m)
            .padding(.vertical, model.inspectsSelection ? Spacing.xs : Spacing.s)
            .card(model.inspectsSelection ? .selected : .standard, radius: Radius.s + 2)
            .accessibilityElement(children: .combine)

            Text(verbatim: detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .motion(value: model.inspectsSelection)
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
        HStack(spacing: Spacing.s) {
            Image(systemName: "slider.horizontal.3").foregroundStyle(.secondary)
            Text("\(Text(localizing: profile.name)) (personalized)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: Spacing.xs)
            Button("Restore") { restore() }
                .buttonStyle(.link)
                .font(.footnote.weight(.medium))
                .help("Go back to this profile's settings")
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .card(.raised, radius: Radius.s + 2)
    }
}
