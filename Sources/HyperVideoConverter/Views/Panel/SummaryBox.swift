import SwiftUI

/// The bar docked at the foot of the settings panel: where files go, one status line
/// (progress while running, otherwise what's ready or why Convert is off) and the
/// Convert / Stop buttons. Every row is always there, so the bar keeps one height in
/// every mode and state (as in HyperImage).
struct SummaryBox: View {
    @Environment(AppModel.self) private var model

    /// Height of the status line: progress bar plus its caption.
    static let statusHeight: CGFloat = 30

    var body: some View {
        let progress = model.progress
        let showsProgress = progress.isActive || model.queue.isProcessing && progress.total > 0
        VStack(alignment: .leading, spacing: Spacing.m) {
            destination
            ZStack(alignment: .leading) {
                if showsProgress {
                    ProgressRow(progress: progress).motionTransition(.opacity)
                } else if let reason = model.convertBlockedReason {
                    statusLabel(reason, symbol: "info.circle").motionTransition(.opacity)
                } else {
                    statusLabel(readyText, symbol: "checkmark.circle").motionTransition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, minHeight: Self.statusHeight, maxHeight: Self.statusHeight, alignment: .leading)
            HStack(spacing: Spacing.s) {
                previewButton
                convertButton
                if model.queue.runningCount > 0 || model.queue.isProcessing {
                    Button {
                        model.queue.cancelAll()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .compatGlassButtonStyle()
                    .controlSize(.large)
                    .fixedSize()
                    .help("Cancel every running and waiting conversion")
                    .motionTransition(.pop)
                }
            }
        }
        .motion(value: showsProgress)
        .motion(value: model.convertBlockedReason)
        .motion(value: model.queue.isProcessing)
    }

    private func statusLabel(_ text: String, symbol: String) -> some View {
        Label { Text(verbatim: text) } icon: { Image(systemName: symbol) }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .help(text)
    }

    /// "4 videos ready · 32 MB → ≈ 20 MB" (the size only when the settings make it predictable).
    private var readyText: String {
        let count = model.readySourceCount
        if count == 0 { return String(localized: "\(model.queue.pendingCount) waiting") }
        let ready = count == 1 ? String(localized: "1 video ready") : String(localized: "\(count) videos ready")
        guard model.mode != .upscale else { return ready }
        let estimate = SizeEstimate(model.sources.filter { $0.info != nil && $0.settings.isValid })
        guard let bytes = estimate.estimatedBytes, estimate.originalBytes > 0 else { return ready }
        let after = SizeEstimate.label(bytes: bytes, kind: estimate.kind)
        return ready + " · " + Format.bytes(estimate.originalBytes) + " → " + after
    }

    /// "Save to  [📁 Movies ▾]": a pop-up with the folder's name, like a save panel's.
    private var destination: some View {
        HStack(spacing: Spacing.s) {
            Text("Save to").foregroundStyle(.secondary).fixedSize()
            Spacer(minLength: 0)
            Menu {
                Button("Change Folder…", systemImage: "folder.badge.gearshape") { model.chooseDestination() }
                Button("Show in Finder", systemImage: "folder") { NSWorkspace.shared.open(model.destinationFolder) }
            } label: {
                Label {
                    Text(verbatim: model.destinationFolder.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } icon: {
                    Image(systemName: "folder")
                }
            }
            .menuStyle(.button)
            .compatGlassButtonStyle()
            .controlSize(.small)
            .fixedSize()
            .help(model.destinationFolder.path)
        }
    }

    /// A short real conversion of the selected (or first) video, before committing to all.
    private var previewButton: some View {
        let target = model.selectedSource ?? model.sources.first { $0.info != nil }
        return Button {
            model.ui.previewSourceID = target?.id
        } label: {
            Image(systemName: "rectangle.split.2x1")
        }
        .compatGlassButtonStyle()
        .controlSize(.large)
        .disabled(target?.info == nil || model.queue.runningCount > 0)
        .help("Preview the result on a short clip")
        .accessibilityLabel(Text("Preview Result…"))
    }

    @ViewBuilder
    private var convertButton: some View {
        let ready = model.readySourceCount
        let working = model.queue.runningCount > 0
        let reason = model.convertBlockedReason
        Button {
            model.convertAll()
        } label: {
            HStack(spacing: Spacing.s) {
                if working && ready == 0 {
                    Text("Processing…")
                } else {
                    Image(systemName: model.mode.symbol)
                    Text(verbatim: model.convertButtonTitle).contentTransition(.numericText())
                }
            }
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
        }
        .compatGlassProminentButtonStyle()
        .controlSize(.large)
        .disabled(reason != nil || (working && ready == 0))
        .keyboardShortcut(.return, modifiers: .command)
        .help(reason.map { Text(verbatim: $0) } ?? Text("Queue every ready video and start (⌘↩)"))
        .motion(Motion.snappy, value: model.convertButtonTitle)
    }
}

private struct ProgressRow: View {
    let progress: QueueProgress

    var body: some View {
        VStack(spacing: Spacing.xs) {
            ProgressView(value: progress.fraction)
                .progressViewStyle(.linear)
                .motion(Motion.snappy, value: progress.fraction)
            HStack {
                Text("File \(progress.current) of \(progress.total)")
                Spacer()
                Text(progress.fraction, format: .percent.precision(.fractionLength(0)))
                    .contentTransition(.numericText())
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .motion(Motion.snappy, value: progress.fraction)
        }
    }
}
