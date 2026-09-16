import Foundation

@MainActor
@Observable
final class SearchHistory {
    static let shared = SearchHistory()
    private(set) var keywords: [String]
    private let defaults: UserDefaults
    private let key = "neobili.searchHistory"
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        keywords = Array((defaults.stringArray(forKey: key) ?? []).prefix(30))
    }
    func record(_ text: String) {
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }
        keywords.removeAll { $0.caseInsensitiveCompare(word) == .orderedSame }
        keywords.insert(word, at: 0)
        keywords = Array(keywords.prefix(30))
        defaults.set(keywords, forKey: key)
    }
    func clear() {
        keywords = []
        defaults.removeObject(forKey: key)
    }
}
