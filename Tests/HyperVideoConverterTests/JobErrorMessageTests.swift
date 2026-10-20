import Foundation
import Testing
import HyperVideoCore
@testable import HyperVideoConverter

@Suite("Job error message")
struct JobErrorMessageTests {
    @Test func insufficientSpaceShowsBothSizes() {
        let text = JobErrorMessage.text(for: TranscodeError.insufficientSpace(required: 2_000_000_000, available: 500_000_000))
        #expect(text.hasPrefix("There isn't enough free space"))
        #expect(text.contains(ByteCountFormatter.string(fromByteCount: 2_000_000_000, countStyle: .file)))
        #expect(text.contains(ByteCountFormatter.string(fromByteCount: 500_000_000, countStyle: .file)))
    }

    @Test func otherErrorsKeepTheirDescription() {
        let error = TranscodeError.stalled
        #expect(JobErrorMessage.text(for: error) == error.localizedDescription)
    }
}
