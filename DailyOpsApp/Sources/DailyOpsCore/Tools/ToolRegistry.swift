import Foundation
import AppKit

public final class ToolRegistry: @unchecked Sendable {
    public static let shared = ToolRegistry()

    private var tools: [String: any DailyOpsTool] = [:]
    private let queue = DispatchQueue(label: "com.dailyops.toolregistry", attributes: .concurrent)

    private init() {
        registerBuiltinTools()
    }

    public func register(_ tool: any DailyOpsTool) {
        queue.async(flags: .barrier) {
            self.tools[tool.id] = tool
        }
    }

    public func unregister(_ toolId: String) {
        queue.async(flags: .barrier) {
            self.tools.removeValue(forKey: toolId)
        }
    }

    public func tool(id: String) -> (any DailyOpsTool)? {
        queue.sync { tools[id] }
    }

    public func allTools() -> [any DailyOpsTool] {
        queue.sync { Array(tools.values) }
    }

    public func tools(in category: ToolCategory) -> [any DailyOpsTool] {
        queue.sync { tools.values.filter { $0.category == category } }
    }

    public func safeTools() -> [any DailyOpsTool] {
        queue.sync { tools.values.filter { $0.riskLevel == .safe } }
    }

    private func registerBuiltinTools() {
        register(OpenApplicationTool())
        register(GetCurrentTimeTool())
        register(CreateLocalNoteTool())
        register(SystemStatusTool())
    }
}

private struct OpenApplicationTool: DailyOpsTool {
    let id = "open_application"
    let name = "Open Application"
    let description = "Launch a macOS application by name"
    let category: ToolCategory = .system
    let riskLevel: ActionRiskLevel = .safe

    func execute(parameters: [String: String]) async throws -> ToolResult {
        guard let appName = parameters["application"] else {
            return ToolResult(success: false, error: "Missing 'application' parameter")
        }
        let workspace = NSWorkspace.shared
        let success = workspace.launchApplication(appName)
        return ToolResult(
            success: success,
            output: success ? "Launched \(appName)" : "Failed to launch \(appName)",
            error: success ? nil : "Application not found"
        )
    }
}

private struct GetCurrentTimeTool: DailyOpsTool {
    let id = "get_current_time"
    let name = "Get Current Time"
    let description = "Return the current date and time"
    let category: ToolCategory = .system
    let riskLevel: ActionRiskLevel = .safe

    func execute(parameters: [String: String]) async throws -> ToolResult {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return ToolResult(success: true, output: formatter.string(from: Date()))
    }
}

/// Creates a tool that writes a local note to DailyOps-owned storage.
public struct CreateLocalNoteTool: DailyOpsTool {
    public let id = "create_local_note"
    public let name = "Create Local Note"
    public let description = "Create a persistent local note in DailyOps storage"
    public let category: ToolCategory = .productivity
    public let riskLevel: ActionRiskLevel = .confirmationRequired

    public func execute(parameters: [String: String]) async throws -> ToolResult {
        guard let title = parameters["title"], let content = parameters["content"] else {
            return ToolResult(success: false, error: "Missing 'title' or 'content' parameter")
        }

        let notesDir = getNotesDirectory()
        try FileManager.default.createDirectory(at: notesDir, withIntermediateDirectories: true)

        let fileName = "\(title.replacingOccurrences(of: "/", with: "-")).txt"
        let fileURL = notesDir.appendingPathComponent(fileName)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: fileURL)
        }

        let noteContent = """
            # \(title)
            Created: \(DateFormatter.iso8601.string(from: Date()))

            \(content)
            """

        try noteContent.write(to: fileURL, atomically: true, encoding: .utf8)

        return ToolResult(
            success: true,
            output: "Note created at \(fileURL.path)",
            error: nil
        )
    }

    private func getNotesDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("DailyOps/AgentNotes", isDirectory: true)
    }
}

private struct SystemStatusTool: DailyOpsTool {
    let id = "system_status"
    let name = "System Status"
    let description = "Get basic system information"
    let category: ToolCategory = .system
    let riskLevel: ActionRiskLevel = .safe

    func execute(parameters: [String: String]) async throws -> ToolResult {
        let processInfo = ProcessInfo.processInfo
        let output = """
            macOS \(processInfo.operatingSystemVersionString)
            Host: \(processInfo.hostName)
            Processor: \(processInfo.processorCount) cores
            Memory: \(ByteCountFormatter.string(fromByteCount: Int64(processInfo.physicalMemory), countStyle: .memory))
            """
        return ToolResult(success: true, output: output)
    }
}

private extension DateFormatter {
    static let iso8601: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}