import Foundation

/// Matches track languages against a user list by ISO 639-2 code.
public enum LanguageFilter {
    /// ISO 639-2 alpha-3, lowercased; empty, "any", "und" and "zxx" mean no language.
    public static func normalized(_ tag: String) -> String? {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !["", "any", "und", "zxx"].contains(trimmed) else { return nil }
        return Locale.Language(identifier: trimmed).languageCode?.identifier(.alpha3) ?? trimmed
    }

    /// Whether `language` is in `list`; an empty list (or one of only "any") matches everything.
    public static func matches(_ language: String?, in list: [String]) -> Bool {
        let wanted = list.compactMap(normalized)
        if wanted.isEmpty { return true }
        guard let language, let code = normalized(language) else { return false }
        return wanted.contains(code)
    }
}
