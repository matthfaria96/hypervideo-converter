import HyperVideoCore
import SwiftUI

/// Finished, failed and cancelled conversions, newest first.
struct HistoryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var ui = model.ui
        PageScaffold(subtitle: "Finished, failed and cancelled conversions.") {
            Button("Clear History", systemImage: "trash") { ui.confirmingClearHistory = true }
                .compatGlassButtonStyle()
                .disabled(model.historyJobs.isEmpty)
                .confirmationDialog("Clear History?", isPresented: $ui.confirmingClearHistory) {
                    Button("Clear History", role: .destructive) { model.queue.clearFinished() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(verbatim: model.clearHistoryMessage)
                }
        } content: {
            if model.historyJobs.isEmpty {
                EmptyPage(symbol: "clock.arrow.circlepath", text: "Converted videos will appear here.")
                    .motionTransition(.pop)
            } else {
                ListCard {
                    ForEach(model.historyJobs) { job in
                        HistoryRow(job: job)
                            .listCardRow()
                            .motionTransition(.row)
                    }
                }
                .motionTransition(.content)
            }
        }
        .motion(value: model.historyJobs.map(\.id))
    }
}
