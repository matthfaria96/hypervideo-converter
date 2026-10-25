import SwiftUI

/// The top of the settings panel in every mode: the mode's title, who the settings go
/// to, then whatever the mode puts there (preset and tabs, the compress goal…).
struct PanelHeader<Accessory: View, Extra: View>: View {
    @Environment(AppModel.self) private var model
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var extra: Extra

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .center, spacing: Spacing.s) {
                Label(model.mode.shortTitle, systemImage: model.mode.symbol)
                    .font(.title3.weight(.semibold))
                Spacer(minLength: Spacing.s)
                accessory
            }
            // One height whether or not the mode has header buttons, so switching modes
            // doesn't move everything below by a few points.
            .frame(height: 28)
            ScopeChip()
            extra
        }
        .padding(.horizontal, Spacing.l)
        .padding(.top, Spacing.l)
        .padding(.bottom, Spacing.m)
    }
}

extension PanelHeader where Accessory == EmptyView {
    init(@ViewBuilder extra: () -> Extra) {
        self.init(accessory: { EmptyView() }, extra: extra)
    }
}

extension PanelHeader where Accessory == EmptyView, Extra == EmptyView {
    init() {
        self.init(accessory: { EmptyView() }, extra: { EmptyView() })
    }
}
