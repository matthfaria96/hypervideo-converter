import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        List(selection: $model.selection) {
            Section("Activity") {
                QueueSidebarRow(queue: model.queue)
                    .tag(SidebarItem.queue)
            }
            Section("Sources") {
                if model.sources.isEmpty {
                    Text("Drop videos here or press ⌘O")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(model.sources) { source in
                    SourceRow(source: source)
                        .tag(SidebarItem.source(source.id))
                        .contextMenu {
                            Button("Add to Queue", systemImage: "text.badge.plus") { model.enqueue([source.id]) }
                                .disabled(source.info == nil)
                            Button("Show in Finder", systemImage: "folder") { SystemIntegration.reveal([source.url]) }
                            Divider()
                            Button("Remove", systemImage: "trash", role: .destructive) { model.removeSource(source.id) }
                        }
                }
                .onDeleteCommand {
                    if case .source(let id) = model.selection { model.removeSource(id) }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            if model.sources.count > 1 {
                Button("Add All to Queue", systemImage: "text.badge.plus") { model.enqueueAll() }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .padding(12)
            }
        }
    }
}

private struct QueueSidebarRow: View {
    let queue: QueueStore

    var body: some View {
        HStack {
            Label("Queue", systemImage: queue.isProcessing ? "gearshape.2.fill" : "list.bullet.rectangle")
                .symbolEffect(.rotate, isActive: queue.isProcessing)
            Spacer()
            if let progress = queue.overallProgress {
                ProgressView(value: progress)
                    .progressViewStyle(.circular)
                    .controlSize(.small)
            } else if queue.pendingCount > 0 {
                Text("\(queue.pendingCount)")
                    .font(.caption.bold())
                    .monospacedDigit()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .glassEffect(.regular, in: .capsule)
            }
        }
    }
}

private struct SourceRow: View {
    let source: SourceItem

    var body: some View {
        HStack(spacing: 10) {
            thumbnail
                .frame(width: 54, height: 34)
                .clipShape(.rect(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text(source.name).lineLimit(1).truncationMode(.middle)
                subtitle.font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = source.thumbnail {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
        } else {
            Rectangle().fill(.quaternary)
                .overlay {
                    if source.isLoading {
                        Image(systemName: "rays").symbolEffect(.rotate).foregroundStyle(.secondary)
                    } else {
                        Image(systemName: source.errorMessage == nil ? "waveform" : "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                }
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        if let info = source.info {
            Text([info.displaySize.map(Format.size), Format.duration(info.duration)].compactMap { $0 }.joined(separator: " · "))
        } else if let error = source.errorMessage {
            Text(error).lineLimit(1)
        } else {
            Text("Analyzing…")
        }
    }
}
