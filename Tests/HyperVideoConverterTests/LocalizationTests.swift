import Foundation
import Testing
import HyperVideoCore
@testable import HyperVideoConverter

@Suite("Localization")
struct LocalizationTests {
    /// The Brazilian Portuguese table shipped in the app's resources.
    private func portuguese() throws -> Bundle {
        let path = try #require(Bundle.module.path(forResource: "Localizable", ofType: "strings",
                                                    inDirectory: nil, forLocalization: "pt-BR"))
        return try #require(Bundle(path: (path as NSString).deletingLastPathComponent))
    }

    @Test(arguments: [
        ("Convert Videos", "Converter vídeos"),
        ("Output Settings", "Configurações de saída"),
        ("Ready to convert", "Pronto para converter"),
        ("Balanced", "Equilibrado"),
        ("%lld videos in the list", "%lld vídeos na lista")
    ])
    func translatesToPortuguese(key: String, expected: String) throws {
        #expect(try portuguese().localizedString(forKey: key, value: nil, table: nil) == expected)
    }

    @Test func formatsCountsInPortuguese() throws {
        let format = try portuguese().localizedString(forKey: "File %lld of %lld", value: nil, table: nil)
        #expect(String(format: format, 2, 5) == "Arquivo 2 de 5")
    }

    @Test func formatsInsufficientSpaceInPortuguese() throws {
        let key = "There isn't enough free space in the destination folder. This video needs about %@, but only %@ is free."
        let format = try portuguese().localizedString(forKey: key, value: "MISSING", table: nil)
        #expect(String(format: format, "A", "B")
            == "Não há espaço livre suficiente na pasta de destino. Este vídeo precisa de cerca de A, mas só há B livres.")
    }

    @Test func everyQualityProfileIsTranslated() throws {
        let bundle = try portuguese()
        for name in ["Balanced", "High Quality", "Smaller File", "Keep Original", "Quality Profiles"] {
            #expect(bundle.localizedString(forKey: name, value: "MISSING", table: nil) != "MISSING", "\(name)")
        }
    }
}

@Suite("Localization tables")
struct LocalizationTableTests {
    private func table() throws -> [String: String] {
        let path = try #require(Bundle.module.path(forResource: "Localizable", ofType: "strings",
                                                    inDirectory: nil, forLocalization: "pt-BR"))
        return try #require(NSDictionary(contentsOfFile: path) as? [String: String])
    }

    /// Format specifiers (%@, %lld, %1$@, %%…) normalized to their types, in order.
    static func specifiers(_ text: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: "%(?:(\\d+)\\$)?(lld|ld|d|@|lf|f|%)")
        let matches = pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
        let found = matches.compactMap { match -> (Int, String)? in
            let type = String(text[Range(match.range(at: 2), in: text)!])
            guard type != "%" else { return nil }
            return (Range(match.range(at: 1), in: text).flatMap { Int(text[$0]) } ?? 0, type)
        }
        let positional = found.contains { $0.0 > 0 }
        return (positional ? found.sorted { $0.0 < $1.0 } : found).map(\.1)
    }

    @Test func everyTranslationKeepsTheFormatSpecifiers() throws {
        for (key, value) in try table() {
            #expect(Self.specifiers(key) == Self.specifiers(value), "\(key) → \(value)")
        }
    }

    @Test(arguments: [
        "%@ (personalized)", "Editing: all %lld videos", "Editing: %@", "Convert %lld Videos", "Convert 1 Video",
        "Compress %lld Videos", "1 video in the list", "%lld videos in the list", "Removes %@. Your original files aren't deleted.",
        "Unsupported format or damaged file", "Queue finished", "1 video converted", "%lld videos converted",
        "Import “%@”", "Import %lld Folders", "≈ estimate", "up to ~%@", "Balanced Compression",
        "Fast 1080p30", "HQ 1080p30 Surround", "HEVC 10-bit · 2160p · 60 fps · HDR preserved", "Video List"
    ])
    func newKeysAreTranslated(key: String) throws {
        let value = try #require(try table()[key], "missing \(key)")
        #expect(!value.isEmpty)
    }

    @Test func everyBuiltInPresetIsTranslated() throws {
        let table = try table()
        for preset in BuiltInPresets.all + QualityProfile.presets + QualityProfile.compressPresets {
            #expect(table[preset.name] != nil, "\(preset.name)")
            #expect(table[preset.summary] != nil, "\(preset.summary)")
        }
    }

    @Test func termsAreConsistent() throws {
        for (key, value) in try table() {
            #expect(!value.localizedCaseInsensitiveContains("predefinid"), "\(key)")
        }
    }
}
