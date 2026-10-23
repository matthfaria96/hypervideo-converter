import SwiftUI

/// The native sidebar: Library pages and Tools, with the system's selection,
/// materials and collapse behaviour.
struct SidebarView: View {
    @Environment(AppModel.self) private var model
    /// The list's own selection, kept in step with the model in both directions.
    @State private var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                ForEach(SidebarItem.library) { row($0) }
            }
            Section("Tools") {
                ForEach(SidebarItem.tools) { row($0) }
            }
        }
        .listStyle(.sidebar)
        .onAppear { selection = model.sidebarSelection }
        .onChange(of: selection) { _, item in
            if let item, item != model.sidebarSelection { model.sidebarSelection = item }
        }
        .onChange(of: model.sidebarSelection) { _, item in
            if selection != item { selection = item }
        }
        .motion(Motion.quick, value: selection)
    }

    private func row(_ item: SidebarItem) -> some View {
        Label(item.title, systemImage: item.symbol)
            .badge(badge(for: item))
            .tag(item)
            .help(item.title)
    }

    /// Running progress on Conversion, the number of finished items on History.
    private func badge(for item: SidebarItem) -> Text? {
        switch item {
        case .conversion where model.queue.runningCount > 0:
            Text(model.progress.fraction, format: .percent.precision(.fractionLength(0)))
        case .history where !model.historyJobs.isEmpty:
            Text(model.historyJobs.count, format: .number)
        default:
            nil
        }
    }
}
