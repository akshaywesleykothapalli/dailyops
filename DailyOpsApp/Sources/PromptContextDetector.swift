import AppKit
import Foundation

/// Describes context metadata about the target application receiving dictation.
public struct TargetAppContext: Sendable, Equatable {
    public let bundleIdentifier: String
    public let localizedName: String
    public let isPromptOriented: Bool

    public init(bundleIdentifier: String, localizedName: String, isPromptOriented: Bool) {
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
        self.isPromptOriented = isPromptOriented
    }
}

/// Protocol for detecting whether the active frontmost destination is prompt-oriented.
@MainActor
public protocol PromptContextDetecting {
    func currentTargetContext(for app: NSRunningApplication?) -> TargetAppContext
    func isPromptOriented(bundleIdentifier: String, appName: String) -> Bool
}

extension PromptContextDetecting {
    public func currentTargetContext() -> TargetAppContext {
        currentTargetContext(for: nil)
    }
}

/// Detects whether the active application is an AI prompt assistant, code agent, or developer IDE.
@MainActor
public final class PromptContextDetector: PromptContextDetecting {
    public static let shared = PromptContextDetector()

    public static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "promptAwareDictationEnabled") as? Bool ?? true
    }

    /// Known prompt-oriented applications and developer IDEs.
    public static let defaultPromptBundleIdentifiers: Set<String> = [
        "com.openai.chat",
        "com.openai.codex",
        "com.anthropic.claude",
        "com.github.Copilot",
        "com.todesktop.230313mzl4w4u92", // Cursor
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "dev.zed.Zed",
        "com.sublimetext.4",
        "com.apple.dt.Xcode",
        "com.googlecode.iterm2",
        "com.apple.Terminal",
        "com.mitchellh.ghostty",
        "co.warp.Warp-Stable",
        "com.jetbrains.intellij",
        "com.jetbrains.pycharm",
        "com.jetbrains.webstorm"
    ]

    private init() {}

    public func currentTargetContext(for app: NSRunningApplication? = nil) -> TargetAppContext {
        let resolvedApp = app ?? NSWorkspace.shared.frontmostApplication
        let bundleId = resolvedApp?.bundleIdentifier ?? ""
        let name = resolvedApp?.localizedName ?? "Unknown"
        let isPrompt = Self.isEnabled && isPromptOriented(bundleIdentifier: bundleId, appName: name)

        return TargetAppContext(
            bundleIdentifier: bundleId,
            localizedName: name,
            isPromptOriented: isPrompt
        )
    }

    public func isPromptOriented(bundleIdentifier: String, appName: String) -> Bool {
        if Self.defaultPromptBundleIdentifiers.contains(bundleIdentifier) {
            return true
        }

        let lowerName = appName.lowercased()
        let promptKeywords = ["chatgpt", "claude", "cursor", "copilot", "terminal", "warp", "iterm", "xcode", "code"]
        return promptKeywords.contains(where: { lowerName.contains($0) })
    }
}

/// Processes text specifically when directed to prompt-oriented contexts.
public struct PromptInputProcessor: Sendable {
    /// Formats dictated speech for developer and AI prompt contexts.
    /// Preserves technical terms, symbols, and instruction phrasing while removing verbal speech hesitation.
    public static func processPromptText(_ text: String, protectedWords: [String] = []) -> String {
        var result = text

        // Preserve technical and code-specific patterns (like camelCase, snake_case, code blocks, parameter flags)
        // Ensure prompt instructions like "write a function that", "fix bug where", etc. maintain sharp syntax
        result = TranscriptFormatter.format(result, protectedWords: protectedWords)

        // Apply typography without replacing programmer quotes (backticks or straight quotes in code context)
        // Keep double quotes clean
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
