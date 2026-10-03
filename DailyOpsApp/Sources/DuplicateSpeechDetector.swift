import Foundation

/// Policy for handling accidental repeated sentences or phrases from speech recognition.
public enum RepeatedSpeechHandling: String, CaseIterable, Identifiable, Sendable {
    case off
    case conservative
    case automatic

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .off: "Off"
        case .conservative: "Conservative"
        case .automatic: "Automatic"
        }
    }

    public var description: String {
        switch self {
        case .off:
            "Keep all transcribed phrases exactly as spoken."
        case .conservative:
            "Only deduplicate high-confidence exact adjacent sentences."
        case .automatic:
            "Remove adjacent sentence and clause repetitions with smart intent detection."
        }
    }
}

/// Detects and deduplicates accidental immediate speech repetitions.
public struct DuplicateSpeechDetector: Sendable {
    public static var configuredMode: RepeatedSpeechHandling {
        guard let raw = UserDefaults.standard.string(forKey: "repeatedSpeechHandling") else {
            return .conservative
        }
        return RepeatedSpeechHandling(rawValue: raw) ?? .conservative
    }

    /// Cleans accidental immediate duplicate sentences based on the given policy.
    public static func process(_ text: String, mode: RepeatedSpeechHandling = configuredMode) -> String {
        guard mode != .off else { return text }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }

        // Split text into candidate sentence chunks preserving delimiters
        let sentences = splitIntoSentences(trimmed)
        guard sentences.count >= 2 else { return text }

        var result: [String] = []
        var i = 0

        while i < sentences.count {
            let current = sentences[i]

            // Check if next sentence is an accidental immediate repetition
            if i + 1 < sentences.count {
                let next = sentences[i + 1]

                if isAccidentalRepetition(first: current, second: next, mode: mode) {
                    // Accidental repetition detected: keep current, skip the duplicate
                    result.append(current)
                    i += 2
                    continue
                }
            }

            result.append(current)
            i += 1
        }

        return result.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Determines if `second` is an accidental repetition of `first`.
    public static func isAccidentalRepetition(
        first: String,
        second: String,
        mode: RepeatedSpeechHandling
    ) -> Bool {
        let normFirst = normalizeForComparison(first)
        let normSecond = normalizeForComparison(second)

        // Ignore empty or extremely short tokens (e.g. single letters or numbers)
        guard !normFirst.isEmpty, !normSecond.isEmpty else { return false }

        // Protection: Check for contextual intentional repetition triggers in first or second
        let intentionalTriggers = [
            "repeat after me",
            "say again",
            "repeat this",
            "repeat that",
            "echo",
            "say:",
            "repeat:"
        ]
        let lowerFirst = first.lowercased()
        if intentionalTriggers.contains(where: { lowerFirst.contains($0) }) {
            return false
        }

        // Case 1: Exact normalized match
        if normFirst == normSecond {
            let words = normFirst.split(separator: " ")
            if mode == .conservative {
                // In conservative mode, require at least 2 words or a non-trivial command
                return words.count >= 2 || normFirst.count >= 4
            } else {
                // In automatic mode, any single non-trivial token or sentence
                return true
            }
        }

        // Case 2: Near-identical match (Automatic mode only)
        if mode == .automatic {
            let wordsFirst = normFirst.split(separator: " ")
            let wordsSecond = normSecond.split(separator: " ")
            if wordsFirst.count >= 3 && wordsSecond.count >= 3 {
                let similarity = jaccardSimilarity(wordsFirst, wordsSecond)
                if similarity >= 0.75 {
                    return true
                }
            }
        }

        return false
    }

    /// Normalizes sentence for comparison (lowercased, stripped punctuation, normalized whitespace).
    public static func normalizeForComparison(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.punctuationCharacters)
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// Splits string into sentences preserving clause and punctuation boundaries.
    private static func splitIntoSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        var current = ""

        let punctuation: Set<Character> = [".", "!", "?", ";", "\n"]

        for char in text {
            current.append(char)
            if punctuation.contains(char) {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    sentences.append(trimmed)
                }
                current = ""
            }
        }

        let remaining = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty {
            sentences.append(remaining)
        }

        return sentences
    }

    private static func jaccardSimilarity(_ a: [Substring], _ b: [Substring]) -> Double {
        let setA = Set(a)
        let setB = Set(b)
        let intersection = setA.intersection(setB).count
        let union = setA.union(setB).count
        guard union > 0 else { return 0.0 }
        return Double(intersection) / Double(union)
    }
}
