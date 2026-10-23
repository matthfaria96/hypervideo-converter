import Foundation
import Testing
@testable import HyperVideoConverter

/// Strings added or changed by the phase 03.1 UI review fixes.
@Suite("Review fix strings")
struct ReviewFixLocalizationTests {
    private func table() throws -> [String: String] {
        let path = try #require(Bundle.module.path(forResource: "Localizable", ofType: "strings",
                                                    inDirectory: nil, forLocalization: "pt-BR"))
        return try #require(NSDictionary(contentsOfFile: path) as? [String: String])
    }

    @Test(arguments: [
        "%lld tracks",
        "Chapters not exported",
        "Give every video in the list these settings (each keeps its own trim, crop, burned-in subtitle, track lists, chapter names and title)",
        "Gives %@ these settings. Each keeps its own trim, crop, burned-in subtitle, track lists, chapter names and title.",
        "Only these tracks are kept, each with its own encoding. Quality profiles and presets set their encoder and bitrate.",
        "Chapter %lld title",
        "Saves this video's output settings as a reusable preset."
    ])
    func isTranslated(key: String) throws {
        let value = try #require(try table()[key], "missing \(key)")
        #expect(!value.isEmpty)
    }
}
