import AppKit
import Foundation

enum TextCapitalizationStyle: String, CaseIterable, Identifiable {
    case preserve
    case sentence
    case title

    var id: String { rawValue }

    var label: String {
        switch self {
        case .preserve: "Preserve"
        case .sentence: "Sentence"
        case .title: "Title"
        }
    }
}

// MARK: - Speech Cleanup Stage

/// Cleans obvious transcription artifacts (fillers, stutters/repeated words, awkward spacing)
/// while strictly preserving original meaning.
enum SpeechCleanup {
    /// Strips excessive conversational fillers when enabled.
    static func removeFillers(_ text: String) -> String {
        text.replacingOccurrences(
            of: "\\b(um+|uh+|erm|hmm|uhm|you know)\\b[ ,]*",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    /// Strips adjacent duplicate words caused by stuttering or speech recognition artifacts.
    /// Preserves the casing of the leading word (e.g. "The the" -> "The").
    static func removeRepeatedWords(_ text: String) -> String {
        let pattern = "\\b([A-Za-z0-9]+)\\s+\\1\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        var current = text
        for _ in 0..<3 {
            let ns = current as NSString
            let matches = regex.matches(in: current, range: NSRange(location: 0, length: ns.length))
            if matches.isEmpty { break }
            for match in matches.reversed() {
                let firstWordRange = match.range(at: 1)
                let firstWord = ns.substring(with: firstWordRange)
                current = (current as NSString).replacingCharacters(in: match.range, with: firstWord)
            }
        }
        return current
    }

    /// Handles spoken self-corrections such as "send it to John — no, send it to Sarah".
    static func handleSelfCorrections(_ text: String) -> String {
        let pattern = #"(?:[A-Za-z0-9]+(?:\s+[A-Za-z0-9]+){0,4})\s+(?:—|--|-|,)\s*(?:no|sorry|scratch that|wait|rather)\s*,\s*"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let ns = text as NSString
        guard regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) != nil else {
            return text
        }
        return regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: "")
    }

    /// Runs all enabled speech cleanup rules.
    static func clean(
        _ text: String,
        removeFillers: Bool = true,
        removeRepeats: Bool = true,
        handleSelfCorrections: Bool = false
    ) -> String {
        var result = text
        if removeFillers {
            result = self.removeFillers(result)
        }
        if removeRepeats {
            result = self.removeRepeatedWords(result)
        }
        if handleSelfCorrections {
            result = self.handleSelfCorrections(result)
        }
        return result
    }
}

// MARK: - Native Spelling Correction Stage

/// On-device spelling correction using Apple's official NSSpellChecker.
/// Corrects genuine typos and errors locally with zero cloud dependencies,
/// while protecting user-defined custom vocabulary.
enum NativeSpellingCorrection {
    static func correctSpelling(_ text: String, protectedWords: Set<String> = []) -> String {
        guard !text.isEmpty else { return text }
        let checker = NSSpellChecker.shared
        let language = checker.language()
        var result = text
        var offset = 0

        while offset < (result as NSString).length {
            let currentNSString = result as NSString
            var wordCount = 0
            let misspelled = checker.checkSpelling(
                of: result,
                startingAt: offset,
                language: language,
                wrap: false,
                inSpellDocumentWithTag: 0,
                wordCount: &wordCount
            )

            if misspelled.location == NSNotFound || misspelled.location < offset {
                break
            }

            let misspelledWord = currentNSString.substring(with: misspelled)
            // Never alter terms explicitly added to the user's custom vocabulary
            if protectedWords.contains(misspelledWord.lowercased()) {
                offset = misspelled.location + misspelled.length
                continue
            }

            if let correction = checker.correction(
                forWordRange: misspelled,
                in: result,
                language: language,
                inSpellDocumentWithTag: 0
            ), !correction.isEmpty, correction.lowercased() != misspelledWord.lowercased() {
                // Preserve initial capitalization if original word was uppercase
                let adjustedCorrection: String
                if let first = misspelledWord.first, first.isUppercase {
                    adjustedCorrection = correction.prefix(1).uppercased() + correction.dropFirst()
                } else {
                    adjustedCorrection = correction
                }

                result = (result as NSString).replacingCharacters(in: misspelled, with: adjustedCorrection)
                offset = misspelled.location + (adjustedCorrection as NSString).length
            } else {
                offset = misspelled.location + misspelled.length
            }
        }
        return result
    }
}

// MARK: - Smart Typography Stage

/// Native system text transformations for quotes, dashes, ellipses, and spacing.
enum SmartTypography {
    static func apply(_ text: String) -> String {
        var result = text

        // 1. Ellipsis: "..." -> "…"
        result = result.replacingOccurrences(of: "...", with: "…")

        // 2. Em dashes: "---", " -- ", "--" -> " — "
        result = result.replacingOccurrences(of: "---", with: "—")
        result = result.replacingOccurrences(of: " -- ", with: " — ")
        result = result.replacingOccurrences(of: "--", with: "—")

        // 3. En dashes for numeric/date ranges: "2020-2025" or "10 - 20" -> "2020–2025"
        result = result.replacingOccurrences(
            of: "(?<=\\d)\\s*-\\s*(?=\\d)",
            with: "–",
            options: .regularExpression
        )

        // 4. Curly quotes & apostrophes
        result = applySmartQuotes(result)

        return result
    }

    private static func applySmartQuotes(_ text: String) -> String {
        var result = ""
        var inDoubleQuote = false
        var inSingleQuote = false
        let chars = Array(text)

        for i in 0..<chars.count {
            let ch = chars[i]
            if ch == "\"" {
                if !inDoubleQuote {
                    result.append("“")
                    inDoubleQuote = true
                } else {
                    result.append("”")
                    inDoubleQuote = false
                }
            } else if ch == "'" {
                let isPrevLetter = i > 0 && (chars[i - 1].isLetter || chars[i - 1].isNumber)
                let isNextLetter = i + 1 < chars.count && (chars[i + 1].isLetter || chars[i + 1].isNumber)
                if isPrevLetter && isNextLetter {
                    // Contraction or possessive apostrophe (e.g. don’t, it’s, Wesley’s)
                    result.append("’")
                } else if !inSingleQuote {
                    result.append("‘")
                    inSingleQuote = true
                } else {
                    result.append("’")
                    inSingleQuote = false
                }
            } else {
                result.append(ch)
            }
        }
        return result
    }
}

// MARK: - Unified Transcript Formatter

enum TranscriptFormatter {
    /// Formats raw text according to user preferences in Settings.
    static func format(_ text: String, protectedWords: [String] = []) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return result }

        let smartFormattingEnabled = UserDefaults.standard.object(forKey: "smartFormattingEnabled") as? Bool ?? true
        let speechCleanupEnabled = UserDefaults.standard.object(forKey: "speechCleanupEnabled") as? Bool ?? true
        let formatSpellCheck = UserDefaults.standard.object(forKey: "formatSpellCheck") as? Bool ?? true
        let smartTypographyEnabled = UserDefaults.standard.object(forKey: "formatSmartTypography") as? Bool ?? true

        // Stage 1: Spoken Punctuation
        if UserDefaults.standard.object(forKey: "formatSpokenPunctuation") as? Bool ?? true {
            result = applySpokenPunctuation(result)
        }

        // Stage 2: Speech Cleanup (Fillers and Repeated Stutters)
        if speechCleanupEnabled {
            let trimFillers = UserDefaults.standard.object(forKey: "cleanRemoveFillers") as? Bool
                ?? UserDefaults.standard.object(forKey: "formatTrimFillers") as? Bool
                ?? true
            let trimRepeats = UserDefaults.standard.object(forKey: "cleanRemoveRepeats") as? Bool ?? true
            let selfCorrect = UserDefaults.standard.object(forKey: "formatSelfCorrection") as? Bool ?? true
            result = SpeechCleanup.clean(result, removeFillers: trimFillers, removeRepeats: trimRepeats, handleSelfCorrections: selfCorrect)
        }

        // Stage 3: Native Spelling Correction (Apple NSSpellChecker)
        if formatSpellCheck {
            let protectedSet = Set(protectedWords.map { $0.lowercased() })
            result = NativeSpellingCorrection.correctSpelling(result, protectedWords: protectedSet)
        }

        // Stage 4: Spacing and Text Structure
        if (UserDefaults.standard.object(forKey: "formatTightenSpacing") as? Bool ?? true) || smartFormattingEnabled {
            result = tightenSpacing(result)
        }

        // Stage 5: Capitalization
        if smartFormattingEnabled {
            let style = TextCapitalizationStyle(
                rawValue: UserDefaults.standard.string(forKey: "formatCapitalization") ?? ""
            ) ?? .sentence
            switch style {
            case .preserve:
                break
            case .sentence:
                result = sentenceCase(result)
            case .title:
                result = result.localizedCapitalized
            }
        }

        // Stage 6: Smart Typography (Curly quotes, em-dashes, ellipses)
        if smartTypographyEnabled {
            result = SmartTypography.apply(result)
        }

        // Stage 7: Terminal Punctuation
        if UserDefaults.standard.object(forKey: "formatAutoPeriod") as? Bool ?? true {
            result = appendTerminalPunctuationIfNeeded(result)
        }

        return result
    }

    private static func applySpokenPunctuation(_ text: String) -> String {
        var result = text
        let replacements: [(String, String)] = [
            ("new paragraph", "\n\n"),
            ("new line", "\n"),
            ("question mark", "?"),
            ("exclamation point", "!"),
            ("exclamation mark", "!"),
            ("semicolon", ";"),
            ("colon", ":"),
            ("comma", ","),
            ("period", "."),
            ("open quote", "“"),
            ("close quote", "”"),
            ("open quotes", "“"),
            ("close quotes", "”"),
        ]
        for (spoken, mark) in replacements {
            result = result.replacingOccurrences(
                of: "\\b\(NSRegularExpression.escapedPattern(for: spoken))\\b",
                with: mark,
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return result
    }

    private static func tightenSpacing(_ text: String) -> String {
        var result = text
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " +([,.;:?!])", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "([,.;:?!])([^\\s\\n0-9\"'”’])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: " *\\n *", with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return result
    }

    private static func sentenceCase(_ text: String) -> String {
        var result = ""
        var shouldCapitalize = true
        for character in text {
            if shouldCapitalize, character.isLetter {
                result.append(String(character).localizedUppercase)
                shouldCapitalize = false
            } else {
                result.append(character)
            }
            if ".?!\n".contains(character) {
                shouldCapitalize = true
            }
        }
        return result
    }

    private static func appendTerminalPunctuationIfNeeded(_ text: String) -> String {
        guard let last = text.last, !".?!:;".contains(last), !last.isNewline else { return text }
        return text + "."
    }
}
