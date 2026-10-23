import Foundation
import Testing
import HyperVideoCore
@testable import HyperVideoConverter

/// Text fields whose model value is normalized keep the raw typing until commit.
@Suite("Text drafts")
struct TextDraftTests {
    @Test func typingKeepsSeparatorsUntilCommit() {
        var stored: [String] = ["eng"]
        var draft = TextDraft(LanguageList.format(stored))
        draft.edit("eng,")
        draft.sync(LanguageList.format(stored))
        #expect(draft.text == "eng,", "the model doesn't reformat what is being typed")
        draft.edit("eng, por")
        stored = LanguageList.parse(draft.commit())
        draft.sync(LanguageList.format(stored))
        #expect(stored == ["eng", "por"] && draft.text == "eng, por" && !draft.isEditing)
    }

    @Test func chapterTitleKeepsSpacesAndBlankWhileTyping() {
        let chapters = [Chapter(title: "Intro", start: 0, duration: 10)]
        var options = ChapterOptions()
        let current = { ChapterEditing.title(at: 0, chapters: chapters, titles: options.titles) }
        var draft = TextDraft(current())
        draft.edit("")
        draft.sync(current())
        #expect(draft.text == "", "clearing the field doesn't bring the source title back mid-edit")
        draft.edit("Opening ")
        #expect(draft.text == "Opening ")
        options = ChapterEditing.settingTitle(draft.commit(), at: 0, chapters: chapters, options: options)
        draft.sync(current())
        #expect(options.titles == ["Opening"] && draft.text == "Opening")
    }

    @Test func externalChangesShowWhenNotTyping() {
        var draft = TextDraft("a")
        draft.sync("b")
        #expect(draft.text == "b")
    }
}
