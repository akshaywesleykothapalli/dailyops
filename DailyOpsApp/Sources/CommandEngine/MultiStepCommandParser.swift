import Foundation

/// Composes multiple child parsers, returning the first successfully parsed plan.
@MainActor
struct CompositeCommandParser: CommandParsing {
    let parsers: [CommandParsing]

    init(parsers: [CommandParsing]) {
        self.parsers = parsers
    }

    func parse(_ transcript: String, context: CommandContext) -> CommandPlan? {
        for parser in parsers {
            if let plan = parser.parse(transcript, context: context) {
                return plan
            }
        }
        return nil
    }
}

/// Parses deterministic multi-step command sequences separated by explicit conjunctions.
/// Checks single-command parsers first so commands containing natural conjunctions
/// (e.g. "search Google for rock and roll") are never mistakenly split.
@MainActor
struct MultiStepCommandParser: CommandParsing {
    private let singleParser: CommandParsing

    init(singleParser: CommandParsing) {
        self.singleParser = singleParser
    }

    init(parsers: [CommandParsing]) {
        self.singleParser = CompositeCommandParser(parsers: parsers)
    }

    func parse(_ transcript: String, context: CommandContext) -> CommandPlan? {
        guard context.isCommandModeEnabled else { return nil }
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".?!"))
        guard !trimmed.isEmpty else { return nil }

        // 1. If the entire transcript parses as a single command, return it directly.
        if let singlePlan = singleParser.parse(trimmed, context: context) {
            return singlePlan
        }

        // 2. Otherwise, attempt sequence splitting on explicit conjunctions.
        return parseSequence(trimmed, context: context)
    }

    private func parseSequence(_ text: String, context: CommandContext) -> CommandPlan? {
        let conjunctions = [
            ", and then ",
            " and then ",
            ", then ",
            " then ",
            ", after that ",
            " after that ",
            ", and ",
            " and ",
            ", "
        ]

        for conjunction in conjunctions {
            // Find all candidate ranges for this conjunction to allow backtracking
            var searchRange = text.startIndex..<text.endIndex
            while let range = text.range(of: conjunction, options: [.caseInsensitive], range: searchRange) {
                let firstPart = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                let secondPart = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)

                if !firstPart.isEmpty && !secondPart.isEmpty {
                    if let firstPlan = singleParser.parse(firstPart, context: context) ?? parseSequence(firstPart, context: context) {
                        let secondPlan: CommandPlan?
                        let hasCompoundConjunction = secondPart.contains(", and ")
                            || secondPart.contains(" and then ")
                            || secondPart.contains(", then ")
                            || secondPart.contains(", after that ")
                            || secondPart.contains(" after that ")
                            || secondPart.contains(", ")

                        if hasCompoundConjunction {
                            secondPlan = parseSequence(secondPart, context: context)
                        } else if let directSecond = singleParser.parse(secondPart, context: context) {
                            secondPlan = directSecond
                        } else {
                            secondPlan = parseSequence(secondPart, context: context)
                        }

                        if let secondPlan {
                            let combinedSteps = firstPlan.steps + secondPlan.steps
                            return CommandPlan(steps: combinedSteps)
                        }
                    }
                }

                // Advance search past this occurrence
                if range.upperBound < text.endIndex {
                    searchRange = range.upperBound..<text.endIndex
                } else {
                    break
                }
            }
        }

        return nil
    }
}
