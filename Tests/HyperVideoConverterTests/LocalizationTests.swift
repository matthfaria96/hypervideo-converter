import Foundation
import Testing
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
        ("%lld videos in the queue", "%lld vídeos na fila")
    ])
    func translatesToPortuguese(key: String, expected: String) throws {
        #expect(try portuguese().localizedString(forKey: key, value: nil, table: nil) == expected)
    }

    @Test func formatsCountsInPortuguese() throws {
        let format = try portuguese().localizedString(forKey: "File %lld of %lld", value: nil, table: nil)
        #expect(String(format: format, 2, 5) == "Arquivo 2 de 5")
    }

    @Test func everyQualityProfileIsTranslated() throws {
        let bundle = try portuguese()
        for name in ["Balanced", "High Quality", "Smaller File", "Keep Original", "Quality Profiles"] {
            #expect(bundle.localizedString(forKey: name, value: "MISSING", table: nil) != "MISSING", "\(name)")
        }
    }
}
