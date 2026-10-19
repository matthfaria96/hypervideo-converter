import SwiftUI

/// The dashed drop target. Drops land anywhere in the window; this shows where
/// and lights up while a drag hovers. It shrinks to a strip once the list has items.
struct DropZoneView: View {
    @Environment(AppModel.self) private var model
    let compact: Bool

    private var targeted: Bool { model.ui.isDropTargeted }

    var body: some View {
        Group {
            if compact { strip } else { full }
        }
        .frame(maxWidth: .infinity)
        .background(background, in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(targeted ? Theme.accent : Color(hex: 0x595960), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
        .animation(.smooth(duration: 0.2), value: targeted)
        .animation(.smooth(duration: 0.25), value: compact)
    }

    private var background: AnyShapeStyle {
        if targeted { return AnyShapeStyle(Color(hex: 0x342B1B)) }
        return AnyShapeStyle(EllipticalGradient(colors: [Color(hex: 0x292621), Theme.panel], center: .center,
                                                startRadiusFraction: 0, endRadiusFraction: 0.7))
    }

    private var full: some View {
        VStack(spacing: 0) {
            icon(size: 43, font: 22).padding(.bottom, 12)
            Text("Add your videos").font(.system(size: 15, weight: .semibold)).padding(.bottom, 6)
            Text("Drag files or folders here, or choose them on your Mac.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .padding(.bottom, 13)
            chooseButton
            Text("MP4, MOV, M4V, MKV and other formats macOS can read")
                .font(.system(size: 10))
                .foregroundStyle(Theme.faint)
                .padding(.top, 9)
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(minHeight: 170)
    }

    private var strip: some View {
        HStack(spacing: 12) {
            icon(size: 30, font: 15)
            VStack(alignment: .leading, spacing: 2) {
                Text("Add more videos").font(.system(size: 12, weight: .semibold))
                Text("Drop files or folders anywhere in the window.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            chooseButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func icon(size: CGFloat, font: CGFloat) -> some View {
        Image(systemName: "plus")
            .font(.system(size: font, weight: .medium))
            .foregroundStyle(Color(hex: 0xFFBF49))
            .frame(width: size, height: size)
            .background(Color(hex: 0x39332A), in: .rect(cornerRadius: size * 0.3))
    }

    private var chooseButton: some View {
        Button {
            model.isImporting = true
        } label: {
            Label("Choose Videos…", systemImage: "plus")
        }
        .buttonStyle(.primary)
    }
}
