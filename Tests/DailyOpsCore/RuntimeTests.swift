import Testing
import Foundation
@testable import DailyOps

struct DailyOpsRuntimeTests {
    let runtime = DailyOpsRuntime.shared
    let roleEngine = RoleEngine.shared

    @Test("L0 simple command creates plan")
    func l0SimpleCommand() async {
        roleEngine.setRole(.general)

        let result = await runtime.submitGoal("open safari")

        #expect(result.error == nil)
        #expect(result.plan != nil)
        #expect(result.routingDecision.level == .L0)
        #expect(result.goal.status == .executing || result.goal.status == .waitingForApproval)
        #expect(result.plan?.tasks.count ?? 0 >= 1)
    }

    @Test("L4 complex goal creates multi-step plan")
    func l4ComplexGoal() async {
        roleEngine.setRole(.general)

        let result = await runtime.submitGoal("start my workday")

        #expect(result.error == nil)
        #expect(result.plan != nil)
        #expect(result.routingDecision.level == .L4)
        #expect(result.plan?.tasks.count ?? 0 >= 4)
    }

    @Test("Developer role creates developer-specific workday plan")
    func developerWorkdayPlan() async {
        roleEngine.setRole(.developer)

        let result = await runtime.submitGoal("start my workday")

        #expect(result.error == nil)
        #expect(result.plan != nil)
        let tasks = result.plan!.tasks
        #expect(tasks.count >= 6)

        let titles = tasks.map { $0.title.lowercased() }
        #expect(titles.contains { $0.contains("schedule") })
        #expect(titles.contains { $0.contains("development") || $0.contains("tasks") })
        #expect(titles.contains { $0.contains("project") || $0.contains("status") })
        #expect(titles.contains { $0.contains("blocker") })
        #expect(titles.contains { $0.contains("prioritize") })
        #expect(titles.contains { $0.contains("summary") })
    }

    @Test("Manager role creates manager-specific workday plan")
    func managerWorkdayPlan() async {
        roleEngine.setRole(.manager)

        let result = await runtime.submitGoal("start my workday")

        #expect(result.error == nil)
        #expect(result.plan != nil)
        let tasks = result.plan!.tasks
        #expect(tasks.count >= 6)

        let titles = tasks.map { $0.title.lowercased() }
        #expect(titles.contains { $0.contains("meeting") })
        #expect(titles.contains { $0.contains("blocker") })
        #expect(titles.contains { $0.contains("approval") })
        #expect(titles.contains { $0.contains("deadline") })
        #expect(titles.contains { $0.contains("communication") })
        #expect(titles.contains { $0.contains("priorit") })
    }

    @Test("Designer role creates designer-specific workday plan")
    func designerWorkdayPlan() async {
        roleEngine.setRole(.designer)

        let result = await runtime.submitGoal("start my workday")

        #expect(result.error == nil)
        #expect(result.plan != nil)
        let tasks = result.plan!.tasks
        #expect(tasks.count >= 6)

        let titles = tasks.map { $0.title.lowercased() }
        #expect(titles.contains { $0.contains("design") })
        #expect(titles.contains { $0.contains("review") })
        #expect(titles.contains { $0.contains("asset") || $0.contains("handoff") })
        #expect(titles.contains { $0.contains("feedback") || $0.contains("user") })
        #expect(titles.contains { $0.contains("prioritize") || $0.contains("deliver") })
        #expect(titles.contains { $0.contains("brief") || $0.contains("focus") })
    }

    @Test("Review prep differs by role")
    func reviewPrepByRole() async {
        // Developer
        roleEngine.setRole(.developer)
        let devResult = await runtime.submitGoal("prepare me for tomorrow's review")
        #expect(devResult.error == nil)
        let devTitles = devResult.plan!.tasks.map { $0.title.lowercased() }
        #expect(devTitles.contains { $0.contains("commit") || $0.contains("test") || $0.contains("ci") })

        // Manager
        roleEngine.setRole(.manager)
        let mgrResult = await runtime.submitGoal("prepare me for tomorrow's review")
        #expect(mgrResult.error == nil)
        let mgrTitles = mgrResult.plan!.tasks.map { $0.title.lowercased() }
        #expect(mgrTitles.contains { $0.contains("metric") || $0.contains("status") || $0.contains("decision") })

        // Designer
        roleEngine.setRole(.designer)
        let designResult = await runtime.submitGoal("prepare me for tomorrow's review")
        #expect(designResult.error == nil)
        let designTitles = designResult.plan!.tasks.map { $0.title.lowercased() }
        #expect(designTitles.contains { $0.contains("iteration") || $0.contains("prototype") || $0.contains("insight") })
    }

    @Test("Permission decisions included in result")
    func permissionDecisionsIncluded() async {
        roleEngine.setRole(.developer)

        let result = await runtime.submitGoal("start my workday")

        #expect(result.error == nil)
        #expect(result.permissionDecisions.count >= 1)
        #expect(result.permissionDecisions.values.contains(.allowed))
    }

    @Test("Verification runs on generated plan")
    func verificationRuns() async {
        roleEngine.setRole(.general)

        let result = await runtime.submitGoal("start my workday")

        #expect(result.verification != nil)
        // Verification may have suggestions but should approve basic plans
        #expect(result.verification?.approved == true || !result.verification!.issues.isEmpty)
    }

    @Test("Goal has correct metadata")
    func goalMetadata() async {
        roleEngine.setRole(.developer)

        let result = await runtime.submitGoal("start my workday")

        #expect(result.goal.originalText == "start my workday")
        #expect(result.goal.normalizedIntent.contains("start") || result.goal.normalizedIntent.contains("workday"))
        #expect(result.goal.roleContext?.role == .developer)
        #expect(result.goal.complexity == .multiAgent)
        #expect(result.goal.source == .text)
    }

    @Test("Tasks are ordered correctly")
    func tasksOrdered() async {
        roleEngine.setRole(.developer)

        let result = await runtime.submitGoal("start my workday")

        let tasks = result.plan!.tasks
        let orders = tasks.map { $0.order }.sorted()
        #expect(orders == Array(0..<tasks.count))
    }
}