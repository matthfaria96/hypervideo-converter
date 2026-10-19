import SwiftUI

/// The shared frame of the History, Favorites and Analyze pages.
struct PageScaffold<Trailing: View, Content: View>: View {
    let eyebrow: LocalizedStringKey
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(eyebrow).textCase(.uppercase).font(.system(size: 11)).foregroundStyle(Theme.muted)
                        Text(title).font(.system(size: 24, weight: .bold)).kerning(-0.7)
                        Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 8)
                    trailing
                }
                content
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
    }
}

struct EmptyPage: View {
    let symbol: String
    let text: LocalizedStringKey

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 26)).foregroundStyle(Theme.faint)
            Text(text).font(.system(size: 12)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .card(fill: Color(hex: 0x202023))
    }
}
