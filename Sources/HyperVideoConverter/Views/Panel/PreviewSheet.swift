import HyperVideoCore
import SwiftUI

/// "How will it look, and how big?" — a short real conversion with the current
/// settings: the same frame before and after behind a draggable divider, and the
/// size projected from the clip.
struct PreviewSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let sourceID: UUID
    @State private var result: Result<ConversionPreview, Error>?

    private var source: SourceItem? { model.sources.first { $0.id == sourceID } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(Spacing.l)
            Divider()
            footer
        }
        .frame(minWidth: 760, idealWidth: 900, minHeight: 560, idealHeight: 640)
        .task(id: sourceID) { await render() }
    }

    private var header: some View {
        HStack(spacing: Spacing.m) {
            Label("Preview", systemImage: "rectangle.split.2x1").font(.title3.weight(.semibold))
            if let source { Text(source.name).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
            Spacer()
            StatusTag(text: model.mode.tagTitle, symbol: model.mode.symbol, tone: model.mode.tone)
        }
        .padding(Spacing.l)
    }

    @ViewBuilder
    private var content: some View {
        switch result {
        case nil:
            VStack(spacing: Spacing.m) {
                ProgressView().controlSize(.large)
                Text(model.mode == .upscale ? "Upscaling a few frames…" : "Converting a 2-second clip…")
                    .foregroundStyle(.secondary)
            }
        case .failure(let error):
            ContentUnavailableView("Couldn't make the preview", systemImage: "exclamationmark.triangle",
                                   description: Text(verbatim: JobErrorMessage.text(for: error)))
        case .success(let preview):
            VStack(spacing: Spacing.m) {
                CompareSlider(before: preview.original, after: preview.converted)
                facts(preview)
            }
            .motionTransition(.content)
        }
    }

    private func facts(_ preview: ConversionPreview) -> some View {
        HStack(spacing: Spacing.l) {
            if let info = source?.info, let from = info.displaySize, let to = preview.outputSize {
                Label("\(Format.size(from)) → \(Format.size(to))", systemImage: "aspectratio")
            }
            if let projected = preview.projectedBytes, let original = source?.info?.fileBytes {
                Label {
                    Text(verbatim: "\(Format.bytes(original)) → ≈ \(Format.bytes(projected))")
                } icon: {
                    Image(systemName: "internaldrive")
                }
                if let change = SizeChangeLook(before: original, after: projected) { change.tag }
            }
            Spacer()
            Text("Measured on a \(Format.duration(max(1, preview.clipSeconds))) clip")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .monospacedDigit()
    }

    private var footer: some View {
        HStack {
            Button("Make Again", systemImage: "arrow.clockwise") { Task { await render() } }
                .compatGlassButtonStyle()
                .disabled(result == nil)
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .compatGlassProminentButtonStyle()
        }
        .padding(Spacing.l)
    }

    private func render() async {
        result = nil
        guard let source, let info = source.info else { return }
        let settings = model.jobSettings(for: source)
        do {
            let preview = try await PreviewRenderer.render(source: source.url, info: info, settings: settings,
                                                          workRoot: FileManager.default.temporaryDirectory)
            result = .success(preview)
        } catch is CancellationError {
            return
        } catch {
            result = .failure(error)
        }
    }
}

/// Before on the left, after on the right, split by a handle the user drags.
private struct CompareSlider: View {
    let before: NSImage
    let after: NSImage
    @State private var split = 0.5

    var body: some View {
        GeometryReader { proxy in
            let size = fitted(in: proxy.size)
            ZStack(alignment: .leading) {
                Image(nsImage: after).resizable().interpolation(.high)
                Image(nsImage: before).resizable().interpolation(.high)
                    .mask(alignment: .leading) { Rectangle().frame(width: size.width * split) }
                handle(height: size.height).offset(x: size.width * split - 14)
                labels
            }
            .frame(width: size.width, height: size.height)
            .clipShape(.rect(cornerRadius: Radius.m))
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                split = min(1, max(0, value.location.x / size.width))
            })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func fitted(in box: CGSize) -> CGSize {
        let ratio = before.size.width / max(1, before.size.height)
        let width = min(box.width, box.height * ratio)
        return CGSize(width: width, height: width / ratio)
    }

    private func handle(height: CGFloat) -> some View {
        ZStack {
            Rectangle().fill(.white).frame(width: 2, height: height).shadow(radius: 2)
            Image(systemName: "arrow.left.and.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.black)
                .frame(width: 28, height: 28)
                .background(.white, in: .circle)
                .shadow(radius: 3)
        }
        .frame(width: 28)
        .accessibilityHidden(true)
    }

    private var labels: some View {
        VStack {
            HStack {
                StatusTag(text: String(localized: "Original"), tone: .neutral)
                Spacer()
                StatusTag(text: String(localized: "Result"), tone: .accent)
            }
            Spacer()
        }
        .padding(Spacing.s)
    }
}
