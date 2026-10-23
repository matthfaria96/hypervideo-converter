import SwiftUI

/// Text being typed into a field whose model value is normalized (trimmed, parsed).
/// The raw text stays as typed until it's committed, so normalizing never fights the keyboard.
struct TextDraft: Equatable {
    private(set) var text: String
    private(set) var isEditing = false

    init(_ text: String) { self.text = text }

    mutating func edit(_ newText: String) {
        text = newText
        isEditing = true
    }

    /// The model changed: show it, unless the user is typing.
    mutating func sync(_ external: String) {
        if !isEditing { text = external }
    }

    /// Ends the edit and returns the text to store.
    mutating func commit() -> String {
        isEditing = false
        return text
    }
}

/// A text field that writes to `text` only on Return or when it loses focus,
/// then shows the normalized value the binding reads back.
struct CommittingTextField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    @State private var draft = TextDraft("")
    @FocusState private var focused: Bool

    var body: some View {
        TextField(title, text: Binding(get: { draft.text }, set: { draft.edit($0) }))
            .focused($focused)
            .onAppear { draft = TextDraft(text) }
            .onChange(of: text) { _, new in draft.sync(new) }
            .onSubmit(commit)
            .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            .onDisappear(perform: commit)
    }

    private func commit() {
        guard draft.isEditing else { return }
        text = draft.commit()
        draft.sync(text)
    }
}
