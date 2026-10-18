import Foundation

/// A named chapter marker; times are in seconds on the source timeline.
public struct Chapter: Codable, Hashable, Sendable {
    public var title: String
    public var start: Double
    public var duration: Double

    public init(title: String, start: Double, duration: Double) {
        self.title = title
        self.start = start
        self.duration = duration
    }

    public var end: Double { start + duration }

    /// The chapters that overlap `start..<end`, cut to fit it. Chapters shorter than
    /// a frame after cutting are dropped so a trim doesn't leave empty markers.
    public static func clipped(_ chapters: [Chapter], start: Double, end: Double) -> [Chapter] {
        chapters.compactMap { chapter in
            let from = max(chapter.start, start)
            let to = min(chapter.end, end)
            guard to - from >= 0.04 else { return nil }
            return Chapter(title: chapter.title, start: from, duration: to - from)
        }
    }
}
