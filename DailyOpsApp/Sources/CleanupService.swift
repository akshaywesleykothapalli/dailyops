import AppKit
import Foundation

/// Which local LLM polishes transcripts.
enum CleanupEngine: String, CaseIterable, Identifiable {
    /// Apple's built-in on-device foundation model — zero setup.
    case apple
    /// Any model served by a local Ollama instance (llama, qwen, mistral…).
    case ollama

    var id: String { rawValue }

    var label: String {
        switch self {
        case .apple: "Apple Intelligence (built-in)"
        case .ollama: "Ollama (local server)"
        }
    }
}

/// Polishes raw transcripts using on-device deterministic formatting rules.
/// Dictation operates 100% locally with zero external network or model dependency.
struct CleanupService {
    /// Which local LLM polishes transcripts.
    static var configuredEngine: CleanupEngine {
        CleanupEngine(rawValue: UserDefaults.standard.string(forKey: "cleanupEngine") ?? "") ?? .apple
    }

    static var ollamaURL: String {
        UserDefaults.standard.string(forKey: "ollamaURL") ?? "http://localhost:11434"
    }

    static var ollamaModel: String {
        UserDefaults.standard.string(forKey: "ollamaModel") ?? "llama3.2"
    }

    /// Ollama models vary widely in speed, so they get more headroom than
    /// the tightly-bounded Apple model before the raw-transcript fallback.
    static var timeout: Duration {
        configuredEngine == .ollama ? .seconds(8) : .seconds(3)
    }

    static var isAvailable: Bool {
        switch configuredEngine {
        case .apple: return true // Apple Intelligence check would go here
        case .ollama: return true // verified per-request; failures fall back to raw
        }
    }

    /// Settings: cleanup can be disabled entirely, or forced to run on
    /// every dictation instead of only when the heuristic finds work.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "cleanupEnabled") as? Bool ?? true
    }

    static var alwaysPolish: Bool {
        UserDefaults.standard.bool(forKey: "cleanupAlways")
    }

    /// No-op retained for API compatibility.
    static func prewarm(vocabulary: [String] = []) {}

    /// Checks if speech contains elements needing cleanup (filler words,
    /// spoken formatting commands, or stutter-repeats).
    static func needsRewrite(_ raw: String) -> Bool {
        let words = raw.lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)

        let fillers: Set<String> = ["um", "uh", "erm", "hmm", "uhm", "you know"]
        if words.contains(where: { fillers.contains($0) }) { return true }

        // Words that are usually dictated punctuation.
        let commandWords: Set<String> = ["period", "comma", "colon", "semicolon"]
        if words.contains(where: { commandWords.contains($0) }) { return true }

        let commandPairs: Set<[String]> = [
            ["question", "mark"], ["exclamation", "mark"], ["exclamation", "point"],
            ["new", "line"], ["new", "paragraph"], ["quote", "unquote"],
        ]
        for pair in zip(words, words.dropFirst()) where commandPairs.contains([pair.0, pair.1]) {
            return true
        }

        // Adjacent duplicate words are the signature of a self-correction.
        return zip(words, words.dropFirst()).contains { $0 == $1 }
    }

    /// Deterministically cleans and formats speech transcripts on-device.
    static func clean(_ raw: String, vocabulary: [String] = [], formal: Bool = false) async -> String {
        guard isEnabled else { return raw }
        guard raw.split(separator: " ").count > (formal ? 1 : 2) else { return raw }
        if !formal && !alwaysPolish && !needsRewrite(raw) {
            return raw
        }
        return cleanDeterministically(raw, vocabulary: vocabulary, formal: formal)
    }

    /// Purely local, synchronous deterministic cleanup using DailyOps's formatting pipeline.
    static func cleanDeterministically(_ raw: String, vocabulary: [String] = [], formal: Bool = false) -> String {
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return raw }
        return TranscriptFormatter.format(raw, protectedWords: vocabulary)
    }
}
