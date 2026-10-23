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
        /// The value when the key holds a number, nil when missing or not a number.
        func optionalInt(_ key: String) -> Int? { (raw[key] as? NSNumber)?.intValue }
        /// Numbers written either as JSON numbers or as strings ("44.1").
        func looseDouble(_ key: String) -> Double? {
            if let number = raw[key] as? NSNumber { return number.doubleValue }
            return (raw[key] as? String).flatMap(Double.init)
        }
        func strings(_ key: String) -> [String] { raw[key] as? [String] ?? [] }
    }
}
