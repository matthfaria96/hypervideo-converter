import SwiftUI

/// "Apply to All Videos" with its confirmation, for the inline panel and the Advanced sheet.
/// The flag is local, so a panel and a sheet on screen together never share one dialog.
struct ApplyToAllButton: View {
    @Environment(AppModel.self) private var model
    let sourceID: UUID
    @State private var isConfirming = false

    var body: some View {
        Button("Apply to All Videos", systemImage: "square.on.square") { isConfirming = true }
            .help("Give every video in the list these settings (each keeps its own trim, crop, burned-in subtitle, track lists, chapter names and title)")
            .confirmationDialog("Apply to all videos?", isPresented: $isConfirming) {
                Button("Apply to All Videos") { model.applyToAll(from: sourceID) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(verbatim: model.applyToAllMessage(from: sourceID))
            }
    }
}
