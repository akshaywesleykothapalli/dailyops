import Foundation
import AppKit

public struct GitStatusTool: DailyOpsTool {
    public let id = "git_status", name = "Git Status", description = "Read-only project status"
    public let category: ToolCategory = .system
    public let riskLevel: ActionRiskLevel = .safe
    public init() {}
    public func execute(parameters: [String: String]) async throws -> ToolResult {
        try await ReadOnlyGit.run(path: parameters["path"] ?? "", arguments: ["status", "--short", "--branch"])
    }
}
public struct GitBranchTool: DailyOpsTool {
    public let id = "git_branch", name = "Git Branch", description = "Read current branch"
    public let category: ToolCategory = .system
    public let riskLevel: ActionRiskLevel = .safe
    public init() {}
    public func execute(parameters: [String: String]) async throws -> ToolResult {
        try await ReadOnlyGit.run(path: parameters["path"] ?? "", arguments: ["branch", "--show-current"])
    }
}
private enum ReadOnlyGit {
    static func run(path: String, arguments: [String]) async throws -> ToolResult {
        guard !path.isEmpty else { return ToolResult(success: false, error: "Configure a default project in Work Setups first.") }
        let expanded = (path as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/"), FileManager.default.fileExists(atPath: expanded) else { return ToolResult(success: false, error: "Project folder unavailable: \(path)") }
        return try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["--no-optional-locks", "-c", "core.fsmonitor=false", "-c", "core.untrackedCache=false", "-C", expanded] + arguments
            process.environment = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory(), "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_TERMINAL_PROMPT": "0"]
            let pipe = Pipe()
            process.standardOutput = pipe; process.standardError = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(decoding: data, as: UTF8.self)
            return ToolResult(success: process.terminationStatus == 0, output: output, error: process.terminationStatus == 0 ? nil : output)
        }.value
    }
}
public struct OpenPathTool: DailyOpsTool {
    public let id = "open_path", name = "Open Project", description = "Open a configured folder in an editor or Finder"
    public let category: ToolCategory = .system
    public let riskLevel: ActionRiskLevel = .safe
    public init() {}
    public func execute(parameters: [String: String]) async throws -> ToolResult {
        await MainActor.run {
            guard let path = parameters["path"], !path.isEmpty else { return ToolResult(success: false, error: "Configure a default project in Work Setups first.") }
            let expanded = (path as NSString).expandingTildeInPath
            guard expanded.hasPrefix("/"), FileManager.default.fileExists(atPath: expanded) else { return ToolResult(success: false, error: "Project folder unavailable: \(path)") }
            let url = URL(fileURLWithPath: expanded)
            let editor = parameters["application"] ?? ""
            if !editor.isEmpty {
                guard let app = NSWorkspace.shared.fullPath(forApplication: editor) else { return ToolResult(success: false, error: "Editor unavailable: \(editor)") }
                let ok = NSWorkspace.shared.openFile(url.path, withApplication: app)
                return ToolResult(success: ok, output: ok ? "Opened \(path) in \(editor)" : nil, error: ok ? nil : "Could not open project")
            }
            let ok = NSWorkspace.shared.open(url)
            return ToolResult(success: ok, output: ok ? "Opened \(path)" : nil, error: ok ? nil : "Could not open folder")
        }
    }
}
public struct OpenURLTool: DailyOpsTool {
    public let id = "open_url", name = "Open URL", description = "Open a configured HTTP or HTTPS URL"
    public let category: ToolCategory = .system
    public let riskLevel: ActionRiskLevel = .safe
    public init() {}
    public func execute(parameters: [String: String]) async throws -> ToolResult {
        guard let raw = parameters["url"], let url = URL(string: raw), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return ToolResult(success: false, error: "Only HTTP/HTTPS URLs are supported") }
        let ok = await MainActor.run { NSWorkspace.shared.open(url) }
        return ToolResult(success: ok, output: ok ? "Opened \(raw)" : nil, error: ok ? nil : "Could not open URL")
    }
}
public struct ReadClipboardTool: DailyOpsTool {
    public let id = "read_clipboard", name = "Read Clipboard", description = "Read clipboard text with approval"
    public let category: ToolCategory = .system
    public let riskLevel: ActionRiskLevel = .confirmationRequired
    public init() {}
    public func execute(parameters: [String: String]) async throws -> ToolResult {
        await MainActor.run { ToolResult(success: true, output: NSPasteboard.general.string(forType: .string) ?? "Clipboard has no text") }
    }
}
public struct CopyToClipboardTool: DailyOpsTool {
    public let id = "copy_to_clipboard", name = "Copy to Clipboard", description = "Replace clipboard text with approval"
    public let category: ToolCategory = .system
    public let riskLevel: ActionRiskLevel = .confirmationRequired
    public init() {}
    public func execute(parameters: [String: String]) async throws -> ToolResult {
        guard let text = parameters["text"] else { return ToolResult(success: false, error: "Missing text") }
        return await MainActor.run {
            NSPasteboard.general.clearContents()
            return ToolResult(success: NSPasteboard.general.setString(text, forType: .string), output: "Clipboard updated")
        }
    }
}
