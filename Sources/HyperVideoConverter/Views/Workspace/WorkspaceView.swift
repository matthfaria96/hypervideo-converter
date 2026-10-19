import SwiftUI

/// The conversion page: title and mode, drop zone, the list, and the Convert bar.
struct WorkspaceView: View {
    @Environment(AppModel.self) private var model

    private var isEmpty: Bool { model.sources.isEmpty && model.activeJobs.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    heading.padding(.bottom, 20)
                    DropZoneView(compact: !isEmpty)
                    listHeader.padding(.top, 22).padding(.bottom, 10)
                    WorkListView()
                    infoStrip.padding(.top, 13)
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.automatic)
            BottomBar()
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(Theme.background)
        }
        .background(Theme.background)
    }

    private var heading: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("WORKSPACE")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                Text(model.mode == .compress ? "Compress Videos" : "Convert Videos")
                    .font(.system(size: 24, weight: .bold))
                    .kerning(-0.7)
                Text(model.mode == .compress
                     ? "Reduce file sizes while keeping the quality that matters."
                     : "Change the format or reduce the size, without the hassle.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            ModePicker()
        }
    }

    private var listHeader: some View {
        HStack {
            HStack(spacing: 4) {
                Text("Conversion Queue").font(.system(size: 13, weight: .semibold))
                Text(verbatim: "(\(model.sources.count + model.activeJobs.count))")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            if !model.sources.isEmpty {
                Button("Select None") { model.selectedIDs = [] }
                    .buttonStyle(.ghost)
                    .disabled(model.selectedIDs.isEmpty)
            }
            Button("Clear Queue") { model.clearWorkspace() }
                .buttonStyle(.ghost)
                .disabled(model.sources.isEmpty && model.queue.pendingCount == 0)
        }
    }

    private var infoStrip: some View {
        HStack(spacing: 10) {
            Circle().fill(Theme.green).frame(width: 6, height: 6)
            Text("Local processing · Your videos are never uploaded to the cloud")
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.muted)
    }
}

/// Converter | Compressor segmented control in the prototype's style.
private struct ModePicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 2) {
            segment("Convert", .convert)
            segment("Compress", .compress)
        }
        .padding(3)
        .card(fill: Color(hex: 0x2B2B2F), radius: 9)
        .fixedSize()
    }

    private func segment(_ title: LocalizedStringKey, _ mode: WorkMode) -> some View {
        let active = model.mode == mode
        return Button {
            model.setMode(mode)
        } label: {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(active ? .white : Theme.muted)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(active ? Color(hex: 0x49494F) : .clear, in: .rect(cornerRadius: 7))
                .shadow(color: active ? .black.opacity(0.3) : .clear, radius: 1.5, y: 1)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
