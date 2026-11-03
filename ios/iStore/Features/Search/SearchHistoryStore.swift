import Foundation

/// История поисковых запросов в `UserDefaults` (последние 10, без повторов).
final class SearchHistoryStore {
    private static let key = "search.history"
    static let limit = 10

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var items: [String] {
        defaults.stringArray(forKey: Self.key) ?? []
    }

    func add(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var list = items.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        list.insert(trimmed, at: 0)
        defaults.set(Array(list.prefix(Self.limit)), forKey: Self.key)
    }

    func remove(_ query: String) {
        defaults.set(items.filter { $0 != query }, forKey: Self.key)
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
