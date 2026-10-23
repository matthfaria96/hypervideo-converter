import Testing
@testable import HyperVideoConverter

@Suite("Completion alert")
struct CompletionAlertTests {
    @Test func mapsOntoTheTwoStoredSwitches() {
        #expect(CompletionAlert(notify: false, eachJob: false) == .never)
        #expect(CompletionAlert(notify: false, eachJob: true) == .never)
        #expect(CompletionAlert(notify: true, eachJob: false) == .queue)
        #expect(CompletionAlert(notify: true, eachJob: true) == .eachVideo)
        for alert in CompletionAlert.allCases {
            #expect(CompletionAlert(notify: alert.notify, eachJob: alert.eachJob) == alert)
        }
    }
}
