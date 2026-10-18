import SwiftUI

struct EmptyStateView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 26) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 168, height: 168)
                .shadow(color: .orange.opacity(0.35), radius: 30)

            VStack(spacing: 8) {
                Text("HyperVideo Converter")
                    .font(.largeTitle.bold())
                Text("Drop videos anywhere in this window, or open them to get started.\nHardware-accelerated H.264, HEVC, HDR and ProRes.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    Button("Open Video…", systemImage: "plus") { model.isImporting = true }
                        .buttonStyle(.glassProminent)
                    if !model.queue.jobs.isEmpty {
                        Button("View Queue", systemImage: "list.bullet.rectangle") { model.selection = .queue }
                            .buttonStyle(.glass)
                    }
                }
                .controlSize(.extraLarge)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
