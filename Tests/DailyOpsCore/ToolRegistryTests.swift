import Testing
import Foundation
@testable import DailyOps

struct ToolRegistryTests {
    let registry = ToolRegistry.shared

    @Test("Builtin tools are registered")
    func builtinToolsRegistered() {
        let tools = registry.allTools()
        #expect(!tools.isEmpty)

        let ids = Set(tools.map { $0.id })
        #expect(ids.contains("open_application"))
        #expect(ids.contains("get_current_time"))
        #expect(ids.contains("create_local_note"))
        #expect(ids.contains("system_status"))
    }

    @Test("Can retrieve tool by ID")
    func retrieveToolById() {
        let tool = registry.tool(id: "get_current_time")
        #expect(tool != nil)
        #expect(tool?.id == "get_current_time")
        #expect(tool?.name == "Get Current Time")
        #expect(tool?.category == .system)
        #expect(tool?.riskLevel == .safe)
    }

    @Test("Returns nil for unknown tool")
    func unknownToolReturnsNil() {
        let tool = registry.tool(id: "nonexistent_tool")
        #expect(tool == nil)
    }

    @Test("Can query tools by category")
    func queryByCategory() {
        let systemTools = registry.tools(in: .system)
        #expect(!systemTools.isEmpty)
        #expect(systemTools.allSatisfy { $0.category == .system })

        let productivityTools = registry.tools(in: .productivity)
        #expect(!productivityTools.isEmpty)
        #expect(productivityTools.allSatisfy { $0.category == .productivity })
    }

    @Test("Safe tools filter works")
    func safeToolsFilter() {
        let safeTools = registry.safeTools()
        #expect(!safeTools.isEmpty)
        #expect(safeTools.allSatisfy { $0.riskLevel == .safe })

        let openApp = registry.tool(id: "open_application")
        #expect(openApp?.riskLevel == .safe)

        let noteTool = registry.tool(id: "create_local_note")
        #expect(noteTool?.riskLevel == .confirmationRequired)

        let safeIds = Set(safeTools.map { $0.id })
        #expect(safeIds.contains("open_application"))
        #expect(safeIds.contains("get_current_time"))
        #expect(safeIds.contains("system_status"))
        #expect(!safeIds.contains("create_local_note"))
    }

    @Test("Can register and unregister custom tools")
    func registerUnregisterCustomTool() {
        struct CustomTool: DailyOpsTool {
            let id = "custom_test_tool"
            let name = "Custom Test"
            let description = "Test tool"
            let category: ToolCategory = .development
            let riskLevel: ActionRiskLevel = .safe
            func execute(parameters: [String: String]) async throws -> ToolResult {
                ToolResult(success: true, output: "test")
            }
        }

        let customTool = CustomTool()
        registry.register(customTool)

        let retrieved = registry.tool(id: "custom_test_tool")
        #expect(retrieved != nil)
        #expect(retrieved?.id == "custom_test_tool")

        registry.unregister("custom_test_tool")
        let afterUnregister = registry.tool(id: "custom_test_tool")
        #expect(afterUnregister == nil)
    }
}