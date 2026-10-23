import Foundation
import SwiftUI

/// The rows of the native sidebar. Compress is the conversion page in Compress mode.
enum SidebarItem: String, CaseIterable, Identifiable {
    case conversion, history, favorites, compress, analyze
    var id: String { rawValue }

    static let library: [SidebarItem] = [.conversion, .history, .favorites]
    static let tools: [SidebarItem] = [.compress, .analyze]

    var section: AppSection {
        switch self {
        case .conversion, .compress: .conversion
        case .history: .history
        case .favorites: .favorites
        case .analyze: .analyze
        }
    }

    /// The workspace mode the row switches to; nil for pages outside the workspace.
    var mode: WorkMode? {
        switch self {
        case .conversion: .convert
        case .compress: .compress
        default: nil
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .conversion: "Conversion"
        case .history: "History"
        case .favorites: "Favorites"
        case .compress: "Compress"
        case .analyze: "Analyze Video"
        }
    }

    var symbol: String {
        switch self {
        case .conversion: "rectangle.stack"
        case .history: "clock.arrow.circlepath"
        case .favorites: "star"
        case .compress: "arrow.down.to.line"
        case .analyze: "magnifyingglass"
        }
    }

    static func current(section: AppSection, mode: WorkMode) -> SidebarItem {
        switch section {
        case .conversion: mode == .compress ? .compress : .conversion
        case .history: .history
        case .favorites: .favorites
        case .analyze: .analyze
        }
    }
}

extension AppModel {
    /// The sidebar's selection: reading reflects the page, writing navigates. A nil
    /// write (the list losing its selection) leaves the page as it is.
    var sidebarSelection: SidebarItem? {
        get { SidebarItem.current(section: section, mode: mode) }
        set {
            guard let item = newValue else { return }
            if let mode = item.mode { setMode(mode) } else { section = item.section }
        }
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
