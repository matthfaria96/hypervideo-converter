import Foundation
import Testing
import HyperVideoCore
@testable import HyperVideoConverter

/// Chapter CSV import and export problems and decoding.
@Suite("Chapter files")
struct ChapterFileTests {
    @Test func exportProblemsAreNotCalledImports() {
        let failure = ChapterFileProblem.export("Disk full")
        #expect(failure.title == "Chapters not exported" && failure.message == "Disk full")
        #expect(ChapterFileProblem.import("Bad line").title == "Chapters not imported")
    }
}
