import Foundation
import UniformTypeIdentifiers

/// Turns dropped or opened items into the media files they contain.
public enum MediaDiscovery {
    /// Media files among `urls`, expanding folders recursively. Hidden files and
    /// package contents (apps, Photos libraries) are skipped; each folder's files come
    /// in Finder order, and duplicates keep their first position.
    public static func mediaFiles(in urls: [URL]) -> [URL] {
        var seen = Set<URL>()
        return urls.flatMap(expand).filter { seen.insert($0.standardizedFileURL).inserted }
    }

    public static func isMedia(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .audiovisualContent)
    }

    private static func expand(_ url: URL) -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return [] }
        guard isDirectory.boolValue else { return isMedia(url) ? [url] : [] }

        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        let files = enumerator.compactMap { $0 as? URL }.filter { file in
            (try? file.resourceValues(forKeys: Set(keys)).isRegularFile) == true && isMedia(file)
        }
        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}
