import Foundation

public struct VideoChapter: Codable, Hashable, Identifiable, Sendable {
    public let from: Double
    public let to: Double
    public let title: String
    public let imageURL: URL?

    public var id: Self { self }

    public init(from: Double, to: Double, title: String, imageURL: URL? = nil) {
        self.from = from
        self.to = to
        self.title = title
        self.imageURL = imageURL
    }
}

public extension Array where Element == VideoChapter {
    /// Chapters are ordered by start time. A shared boundary starts the next
    /// chapter, while the final endpoint still belongs to the last chapter.
    func chapter(at seconds: Double) -> VideoChapter? {
        guard seconds.isFinite, seconds >= 0 else { return nil }
        return last { $0.from <= seconds && seconds < $0.to }
            ?? last.flatMap { seconds == $0.to ? $0 : nil }
    }
}
