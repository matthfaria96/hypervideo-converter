import Foundation

extension HandBrakePresets {
    /// Typed, forgiving access to a preset dictionary.
    struct Fields {
        let raw: [String: Any]
        init(_ raw: [String: Any]) { self.raw = raw }

        func string(_ key: String) -> String? { raw[key] as? String }
        func bool(_ key: String) -> Bool? { raw[key] as? Bool }
        func double(_ key: String) -> Double? { (raw[key] as? NSNumber)?.doubleValue }
        func int(_ key: String) -> Int { (raw[key] as? NSNumber)?.intValue ?? 0 }
        func strings(_ key: String) -> [String] { raw[key] as? [String] ?? [] }
    }
}
