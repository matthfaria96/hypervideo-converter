import Foundation
import SwiftUI

/// The pages other than the workspace. The window always shows the workspace; these
/// open over it as sheets from the status footer (like HyperImage's sibling layout).
extension AppSection {
    static let pages: [AppSection] = [.history, .favorites, .analyze]

    var title: LocalizedStringKey {
        switch self {
        case .conversion: "Convert Videos"
        case .history: "History"
        case .favorites: "Favorites"
        case .analyze: "Analyze Video"
        }
    }

    var symbol: String {
        switch self {
        case .conversion: "rectangle.stack"
        case .history: "clock.arrow.circlepath"
        case .favorites: "star"
        case .analyze: "magnifyingglass"
        }
    }

    /// Launch argument values (`-InitialSection history`), "compress" included.
    init?(launchName: String) {
        switch launchName {
        case "conversion", "compress": self = .conversion
        case "history": self = .history
        case "favorites": self = .favorites
        case "analyze": self = .analyze
        default: return nil
        }
    }
}

extension AppModel {
    /// The page sheet over the workspace, nil when none is open.
    var presentedPage: AppSection? {
        get { section == .conversion ? nil : section }
        set { section = newValue ?? .conversion }
    }

    /// The conversion list's selection. Queued jobs share the list but can't be
    /// selected, so their IDs are dropped on the way in.
    var listSelection: Set<UUID> {
        get { selectedIDs }
        set { selectedIDs = newValue.intersection(sources.map(\.id)) }
    }

    /// Drag reordering from a native list.
    func moveSources(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        var reordered = sources
        reordered.move(fromOffsets: offsets, toOffset: destination)
        setSources(reordered)
    }
}
