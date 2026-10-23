import SwiftUI

/// The drop target. Drops land anywhere in the window; this shows where and lights
/// up while a drag hovers. The full version fills the empty page; the compact strip
/// sits above the list once it has items.
struct DropZoneView: View {
    @Environment(AppModel.self) private var model
    let compact: Bool

    private var targeted: Bool { model.ui.isDropTargeted }

    var body: some View {
        Group {
            if compact { strip } else { full }
        }
        .frame(maxWidth: .infinity)
        .background(fill, in: .rect(cornerRadius: Radius.l))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.l)
                .strokeBorder(targeted ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.separator),
                              style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
        }
        .scaleEffect(targeted ? 1.01 : 1)
        .motion(Motion.quick, value: targeted)
        .motion(value: compact)
    }

    private var fill: AnyShapeStyle {
        targeted ? AnyShapeStyle(Theme.accent.opacity(0.1)) : AnyShapeStyle(.fill.quaternary)
    }

    private var full: some View {
        VStack(spacing: Spacing.s) {
            icon(size: 64, font: 28).padding(.bottom, Spacing.s)
            Text("Add your videos").font(.title3.weight(.semibold))
            Text("Drag files or folders here, or choose them on your Mac.")
                .foregroundStyle(.secondary)
                .padding(.bottom, Spacing.s)
            chooseButton.controlSize(.large)
            Text("MP4, MOV, M4V, MKV and other formats macOS can read")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.top, Spacing.xs)
        }
        .multilineTextAlignment(.center)
        .padding(Spacing.xxl)
        .frame(minHeight: 260)
    }

    private var strip: some View {
        HStack(spacing: Spacing.m) {
            icon(size: 28, font: 13)
            VStack(alignment: .leading, spacing: 2) {
                Text("Add more videos").font(.callout.weight(.medium))
                Text("Drop files or folders anywhere in the window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Spacing.s)
            chooseButton.controlSize(.small)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
    }

    private func icon(size: CGFloat, font: CGFloat) -> some View {
        Image(systemName: "arrow.down.document.fill")
            .font(.system(size: font, weight: .medium))
            .foregroundStyle(Theme.accent)
            .symbolEffect(.bounce, value: targeted)
            .frame(width: size, height: size)
            .background(Theme.accent.opacity(0.14), in: .rect(cornerRadius: size * 0.28))
    }

    private var chooseButton: some View {
        Button {
            model.isImporting = true
        } label: {
            Label("Choose Videos…", systemImage: "plus")
        }
        .compatGlassProminentButtonStyle()
    }
}
