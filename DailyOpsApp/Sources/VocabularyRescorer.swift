import Foundation

enum VocabularyRescorer {
    private struct Token {
        let text: String
        let normalized: String
        let range: Range<String.Index>
    }

    private struct Candidate {
        let range: Range<String.Index>
        let tokenRange: Range<Int>
        let replacement: String
        let score: Double
    }

    static func rescore(_ text: String, vocabulary: [String], replacements: [String: String]) -> String {
        guard UserDefaults.standard.object(forKey: "vocabularyRescoringEnabled") as? Bool ?? true else {
            return text
        }
        let tokens = tokenize(text)
        guard !tokens.isEmpty else { return text }

        let targets = vocabularyTargets(vocabulary: vocabulary, replacements: replacements)
        guard !targets.isEmpty else { return text }

        var candidates: [Candidate] = []
        for target in targets {
            let targetTokens = target.phrase
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map { normalized(String($0)) }
                .filter { !$0.isEmpty }
            guard !targetTokens.isEmpty else { continue }

            let spanSizes = plausibleSpanSizes(for: targetTokens.count)
            for spanSize in spanSizes {
                guard spanSize <= tokens.count else { continue }
                for start in 0...(tokens.count - spanSize) {
                    let end = start + spanSize
                    let phrase = tokens[start..<end].map(\.normalized).joined(separator: " ")
                    let score = score(candidate: phrase, target: targetTokens.joined(separator: " "))
                    guard score >= threshold(for: target.phrase, tokenCount: targetTokens.count) else { continue }
                    candidates.append(Candidate(
                        range: tokens[start].range.lowerBound..<tokens[end - 1].range.upperBound,
                        tokenRange: start..<end,
                        replacement: target.replacement,
                        score: score
                    ))
                }
            }
        }

        let accepted = candidates
            .sorted { left, right in
                if left.score == right.score {
                    return left.tokenRange.count > right.tokenRange.count
                }
                return left.score > right.score
            }
            .reduce(into: [Candidate]()) { chosen, candidate in
                guard !chosen.contains(where: { overlaps($0.tokenRange, candidate.tokenRange) }) else { return }
                chosen.append(candidate)
            }
            .sorted { $0.range.lowerBound > $1.range.lowerBound }

        var result = text
        for candidate in accepted {
            result.replaceSubrange(candidate.range, with: candidate.replacement)
        }
        return result
    }

    private static func vocabularyTargets(vocabulary: [String], replacements: [String: String]) -> [(phrase: String, replacement: String)] {
        let replacementTargets = replacements.map { (phrase: $0.key, replacement: $0.value) }
        let wordTargets = vocabulary.map { (phrase: $0, replacement: $0) }
        return (replacementTargets + wordTargets)
            .filter { normalized($0.phrase).count >= 4 || $0.phrase.contains(where: \.isWhitespace) }
    }

    private static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var start: String.Index?

        func finish(at end: String.Index) {
            guard let tokenStart = start else { return }
            let raw = String(text[tokenStart..<end])
            let clean = normalized(raw)
            if !clean.isEmpty {
                tokens.append(Token(text: raw, normalized: clean, range: tokenStart..<end))
            }
            start = nil
        }

        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character.isLetter || character.isNumber {
                if start == nil { start = index }
            } else {
                finish(at: index)
            }
            index = text.index(after: index)
        }
        finish(at: text.endIndex)
        return tokens
    }

    private static func plausibleSpanSizes(for count: Int) -> [Int] {
        let lower = max(1, count - 1)
        let upper = count + 1
        return Array(lower...upper)
    }

    private static func threshold(for phrase: String, tokenCount: Int) -> Double {
        let normalizedPhrase = normalized(phrase)
        if tokenCount > 1 { return 0.78 }
        if normalizedPhrase.count <= 5 { return 0.9 }
        return 0.84
    }

    private static func score(candidate: String, target: String) -> Double {
        guard !candidate.isEmpty, !target.isEmpty else { return 0 }
        let lengthRatio = Double(candidate.count) / Double(target.count)
        guard (0.55...1.8).contains(lengthRatio) else { return 0 }

        let textScore = 1 - (Double(editDistance(candidate, target)) / Double(max(candidate.count, target.count)))
        let phoneticScore = 1 - (Double(editDistance(phoneticKey(candidate), phoneticKey(target))) / Double(max(phoneticKey(candidate).count, phoneticKey(target).count, 1)))
        let initialsBonus = initials(candidate) == initials(target) ? 0.05 : 0
        return min(1, max(0, textScore * 0.72 + phoneticScore * 0.28 + initialsBonus))
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0.isWhitespace }
            .split(separator: " ")
            .joined(separator: " ")
    }

    private static func phoneticKey(_ value: String) -> String {
        let normalized = normalized(value)
        var output = ""
        var previous: Character?
        for word in normalized.split(separator: " ") {
            guard let first = word.first else { continue }
            output.append(first)
            for character in word.dropFirst() {
                guard !"aeiou".contains(character) else { continue }
                guard character != previous else { continue }
                output.append(character)
                previous = character
            }
            output.append(" ")
            previous = nil
        }
        return output.trimmingCharacters(in: .whitespaces)
    }

    private static func initials(_ value: String) -> String {
        normalized(value)
            .split(separator: " ")
            .compactMap(\.first)
            .map(String.init)
            .joined()
    }

    private static func overlaps(_ left: Range<Int>, _ right: Range<Int>) -> Bool {
        left.lowerBound < right.upperBound && right.lowerBound < left.upperBound
    }

    private static func editDistance(_ left: String, _ right: String) -> Int {
        let a = Array(left)
        let b = Array(right)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }

        var previous = Array(0...b.count)
        var current = Array(repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + cost
                )
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
