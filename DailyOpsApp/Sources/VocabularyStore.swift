import Foundation

/// User-defined words (names, product terms) the cleanup model should
/// preserve and spell correctly.
@MainActor
@Observable
final class VocabularyStore {
    private static let defaultsKey = "customVocabulary"
    private static let replacementsKey = "dictionaryReplacements"
    private static let starredKey = "dictionaryStarredItems"

    var words: [String] {
        didSet { UserDefaults.standard.set(words, forKey: Self.defaultsKey) }
    }
    var replacements: [String: String] {
        didSet { UserDefaults.standard.set(replacements, forKey: Self.replacementsKey) }
    }
    var starredItems: Set<String> {
        didSet { UserDefaults.standard.set(Array(starredItems), forKey: Self.starredKey) }
    }

    init() {
        words = UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? []
        replacements = UserDefaults.standard.dictionary(forKey: Self.replacementsKey) as? [String: String] ?? [:]
        let savedStarred = UserDefaults.standard.stringArray(forKey: Self.starredKey) ?? []
        starredItems = Set(savedStarred)
    }

    func isStarred(_ key: String) -> Bool {
        starredItems.contains(key)
    }

    func toggleStarred(_ key: String) {
        if starredItems.contains(key) {
            starredItems.remove(key)
        } else {
            starredItems.insert(key)
        }
    }

    func add(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !words.contains(trimmed) else { return }
        words.append(trimmed)
    }

    func remove(_ word: String) {
        words.removeAll { $0 == word }
        starredItems.remove(word)
    }

    func addReplacement(spoken: String, replacement: String) {
        let key = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !value.isEmpty else { return }
        replacements[key] = value
    }

    func removeReplacement(spoken: String) {
        replacements.removeValue(forKey: spoken)
        starredItems.remove(spoken)
    }

    func applyReplacements(to text: String) -> String {
        replacements.reduce(text) { partial, item in
            partial.replacingOccurrences(
                of: "\\b\(NSRegularExpression.escapedPattern(for: item.key))\\b",
                with: item.value,
                options: [.regularExpression, .caseInsensitive]
            )
        }
    }
}
