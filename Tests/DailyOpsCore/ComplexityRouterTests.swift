import Testing
import Foundation
@testable import DailyOps

struct ComplexityRouterTests {
    let router = ComplexityRouter.shared

    @Test("L0 routing for simple commands")
    func l0Routing() {
        let cases = [
            "open safari",
            "launch finder",
            "close window",
            "copy text",
            "paste",
            "mute volume",
            "unmute",
            "volume up",
            "brightness down",
            "take screenshot",
            "lock screen",
            "sleep mac",
            "restart",
            "shutdown"
        ]

        for text in cases {
            let decision = router.route(text, role: .general)
            #expect(decision.level == .L0, "Expected L0 for '\(text)', got \(decision.level)")
            #expect(!decision.reason.isEmpty)
        }
    }

    @Test("L1 routing for text transformations")
    func l1Routing() {
        let cases = [
            "rewrite this paragraph",
            "rephrase that sentence",
            "summarize this document",
            "format the code",
            "clean up the text",
            "fix grammar",
            "translate to spanish"
        ]

        for text in cases {
            let decision = router.route(text, role: .general)
            #expect(decision.level == .L1 || decision.level == .L2, "Expected L1/L2 for '\(text)', got \(decision.level)")
            #expect(!decision.reason.isEmpty)
        }
    }

    @Test("L2 routing for analysis tasks")
    func l2Routing() {
        let cases = [
            "analyze this data",
            "compare these options",
            "find the bug",
            "search for files",
            "lookup the definition",
            "calculate the total",
            "convert units",
            "generate a report"
        ]

        for text in cases {
            let decision = router.route(text, role: .general)
            #expect(decision.level >= .L2, "Expected L2+ for '\(text)', got \(decision.level)")
            #expect(!decision.reason.isEmpty)
        }
    }

    @Test("L4 routing for complex multi-step goals")
    func l4Routing() {
        let cases = [
            "start my workday",
            "prepare me for tomorrow's review",
            "plan my week",
            "organize my tasks",
            "review my progress",
            "catch me up on everything",
            "daily standup preparation",
            "weekly review",
            "end of day summary",
            "prepare for tomorrow's meeting"
        ]

        for text in cases {
            let decision = router.route(text, role: .general)
            #expect(decision.level == .L4, "Expected L4 for '\(text)', got \(decision.level)")
            #expect(decision.reason.contains("multi-step") || decision.reason.contains("contextual"))
        }
    }

    @Test("L4 routing works across all roles")
    func l4AcrossRoles() {
        let text = "start my workday"
        for role in EmployeeRole.allCases {
            let decision = router.route(text, role: role)
            #expect(decision.level == .L4, "Expected L4 for role \(role), got \(decision.level)")
        }
    }

    @Test("Long text defaults to L2")
    func longTextDefault() {
        let longText = "this is a very long request with many words that should trigger higher complexity routing"
        let decision = router.route(longText, role: .general)
        #expect(decision.level >= .L2)
    }
}