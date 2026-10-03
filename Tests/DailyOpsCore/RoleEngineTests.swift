import Testing
import Foundation
@testable import DailyOps

struct RoleEngineTests {
    let engine = RoleEngine.shared

    @Test("Default role is general")
    func defaultRole() {
        #expect(engine.activeRole == .general)
    }

    @Test("Can set and retrieve role")
    func setRole() {
        engine.setRole(.developer)
        #expect(engine.activeRole == .developer)
        #expect(engine.activeProfile.role == .developer)

        engine.setRole(.manager)
        #expect(engine.activeRole == .manager)
        #expect(engine.activeProfile.role == .manager)

        engine.setRole(.designer)
        #expect(engine.activeRole == .designer)
        #expect(engine.activeProfile.role == .designer)

        engine.setRole(.general)
        #expect(engine.activeRole == .general)
    }

    @Test("Each role has distinct profile")
    func distinctProfiles() {
        engine.setRole(.developer)
        let devProfile = engine.activeProfile
        #expect(devProfile.priorities.contains("code quality"))
        #expect(devProfile.commonWorkCategories.contains("repository work"))
        #expect(devProfile.preferredToolCategories.contains(.development))

        engine.setRole(.manager)
        let mgrProfile = engine.activeProfile
        #expect(mgrProfile.priorities.contains("team health"))
        #expect(mgrProfile.commonWorkCategories.contains("meetings"))
        #expect(mgrProfile.preferredToolCategories.contains(.communication))

        engine.setRole(.designer)
        let designProfile = engine.activeProfile
        #expect(designProfile.priorities.contains("design quality"))
        #expect(designProfile.commonWorkCategories.contains("design work"))
        #expect(designProfile.preferredToolCategories.contains(.knowledge))

        engine.setRole(.general)
        let generalProfile = engine.activeProfile
        #expect(generalProfile.priorities.contains("productivity"))
        #expect(generalProfile.preferredToolCategories.contains(.system))
    }

    @Test("Role profiles have contextual hints")
    func contextualHints() {
        engine.setRole(.developer)
        #expect(!engine.activeProfile.contextualHints.isEmpty)

        engine.setRole(.manager)
        #expect(!engine.activeProfile.contextualHints.isEmpty)

        engine.setRole(.designer)
        #expect(!engine.activeProfile.contextualHints.isEmpty)

        engine.setRole(.general)
        #expect(!engine.activeProfile.contextualHints.isEmpty)
    }
}