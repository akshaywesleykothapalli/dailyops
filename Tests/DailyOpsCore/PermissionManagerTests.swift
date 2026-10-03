import Testing
import Foundation
@testable import DailyOps

struct PermissionManagerTests {
    let manager = PermissionManager.shared

    @Test("Safe tools are allowed by default")
    func safeToolsAllowed() {
        let decision = manager.decision(for: .safe)
        #expect(decision == .allowed)
    }

    @Test("Confirmation required tools need confirmation")
    func confirmationRequiredTools() {
        let decision = manager.decision(for: .confirmationRequired)
        #expect(decision == .requiresConfirmation)
    }

    @Test("Critical tools are denied by default")
    func criticalToolsDenied() {
        let decision = manager.decision(for: .critical)
        #expect(decision == .denied)
    }

    @Test("Custom decision overrides default")
    func customDecisionOverride() {
        manager.setCustomDecision(.allowed, forTool: "critical_tool")
        let decision = manager.decision(for: .critical, toolId: "critical_tool")
        #expect(decision == .allowed)

        manager.setCustomDecision(.denied, forTool: "safe_tool")
        let deniedDecision = manager.decision(for: .safe, toolId: "safe_tool")
        #expect(deniedDecision == .denied)

        manager.clearCustomDecision(forTool: "critical_tool")
        manager.clearCustomDecision(forTool: "safe_tool")

        let afterClear = manager.decision(for: .critical, toolId: "critical_tool")
        #expect(afterClear == .denied)
    }

    @Test("Unknown tool ID falls back to risk level default")
    func unknownToolFallback() {
        let decision = manager.decision(for: .confirmationRequired, toolId: "unknown_tool_123")
        #expect(decision == .requiresConfirmation)
    }
}