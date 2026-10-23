import Foundation
import HyperVideoCore

extension AppModel {
    /// Edits one external subtitle file; making it the default clears the flag on the others.
    func updateSubtitleFile(_ url: URL, in sourceID: UUID, _ change: (inout SubtitleFile) -> Void) {
        update(sourceID) { item in
            let becameDefault = item.subtitleFiles.contains { file in
                guard file.url == url, !file.isDefault else { return false }
                var probe = file
                change(&probe)
                return probe.isDefault
            }
            item.subtitleFiles = item.subtitleFiles.map { file in
                if file.url == url {
                    var edited = file
                    change(&edited)
                    return edited
                }
                guard becameDefault, file.isDefault else { return file }
                var other = file
                other.isDefault = false
                return other
            }
        }
    }
}
