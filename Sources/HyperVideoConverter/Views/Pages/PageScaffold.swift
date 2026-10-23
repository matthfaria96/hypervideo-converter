import SwiftUI

/// The shared frame of the History, Favorites and Analyze pages. The page title lives
/// in the window toolbar; the scaffold adds the one-line description and the actions.
struct PageScaffold<Trailing: View, Content: View>: View {
    let subtitle: LocalizedStringKey
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.l) {
                    Text(subtitle).foregroundStyle(.secondary)
                    Spacer(minLength: Spacing.s)
                    trailing
                }
                content
            }
            .padding(Spacing.xl)
            .frame(maxWidth: 960, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .compatSoftScrollEdges()
        .background(Theme.background)
    }
}

/// A list card: rows separated by hairlines inside one rounded panel.
struct ListCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .clipShape(.rect(cornerRadius: Radius.m))
            .card()
    }
}

extension View {
    /// A row of a `ListCard`.
    func listCardRow() -> some View {
        padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.m)
            .overlay(alignment: .bottom) { Divider().padding(.leading, Spacing.l) }
    }
}

struct EmptyPage: View {
    let symbol: String
    let text: LocalizedStringKey

    var body: some View {
        ContentUnavailableView {
            Label(text, systemImage: symbol)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity)
        .card()
    }
}
