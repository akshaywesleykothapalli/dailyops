import XCTest
@testable import DailyOps

/// The validator is the only gate between a parsed plan and a side effect, so
/// these tests describe the risk boundary directly rather than through the
/// router.
@MainActor
final class CommandValidatorTests: XCTestCase {
    private let probe = CommandIdentifier(rawValue: "test.probe")

    private func validator(
        risk: CommandRisk,
        confirmation: ConfirmationRequirement,
        argumentKind: CommandArgumentKind = .none
    ) -> CommandValidator {
        CommandValidator(registry: CommandRegistry(definitions: [
            CommandDefinition(
                identifier: probe,
                name: "Probe",
                risk: risk,
                confirmation: confirmation,
                argumentKind: argumentKind
            )
        ]))
    }

    private func plan(arguments: CommandArguments = .none) -> CommandPlan {
        CommandPlan(intent: CommandIntent(identifier: probe, arguments: arguments))
    }

    // MARK: - Safe

    func testSafeCommandIsApproved() {
        let validation = try? validator(risk: .safe, confirmation: .none).validate(plan(), context: .test())
        XCTAssertEqual(validation, .approved)
    }

    func testSafeCommandWithOptionalConfirmationStillRuns() {
        // `.optional` defers to risk, and a safe command has nothing to defer.
        let validation = try? validator(risk: .safe, confirmation: .optional).validate(plan(), context: .test())
        XCTAssertEqual(validation, .approved)
    }

    // MARK: - Sensitive

    func testSensitiveCommandWithOptionalConfirmationRequiresConfirmation() {
        let validation = try? validator(risk: .sensitive, confirmation: .optional)
            .validate(plan(), context: .test())
        guard case .requiresConfirmation = validation else {
            return XCTFail("expected confirmation, got \(String(describing: validation))")
        }
    }

    func testSensitiveCommandMarkedImmediateIsApproved() {
        // This is how the shipped app.quit / clipboard.clear behave: recorded as
        // sensitive, but still immediate because there is no confirmation UI.
        let validation = try? validator(risk: .sensitive, confirmation: .none)
            .validate(plan(), context: .test())
        XCTAssertEqual(validation, .approved)
    }

    // MARK: - Destructive

    func testDestructiveCommandRequiresConfirmation() {
        let validation = try? validator(risk: .destructive, confirmation: .mandatory)
            .validate(plan(), context: .test())
        guard case .requiresConfirmation = validation else {
            return XCTFail("expected confirmation, got \(String(describing: validation))")
        }
    }

    /// A registry entry claiming a destructive command needs no confirmation is
    /// a mistake, not a policy. The validator must override it rather than let
    /// the command through.
    func testDestructiveCommandIsConfirmedEvenWhenTheRegistrySaysOtherwise() {
        for policy in [ConfirmationRequirement.none, .optional] {
            let validation = try? validator(risk: .destructive, confirmation: policy)
                .validate(plan(), context: .test())
            guard case .requiresConfirmation = validation else {
                return XCTFail("destructive + \(policy) must confirm, got \(String(describing: validation))")
            }
        }
    }

    func testMandatoryConfirmationAppliesAtEveryRiskLevel() {
        for risk in [CommandRisk.safe, .sensitive, .destructive] {
            let validation = try? validator(risk: risk, confirmation: .mandatory)
                .validate(plan(), context: .test())
            guard case .requiresConfirmation = validation else {
                return XCTFail("\(risk) + mandatory must confirm, got \(String(describing: validation))")
            }
        }
    }

    // MARK: - Rejections

    func testUnknownCommandIsRejected() {
        let validator = CommandValidator(registry: CommandRegistry())
        XCTAssertThrowsError(try validator.validate(plan(), context: .test())) { error in
            XCTAssertEqual(error as? CommandValidationError, .unknownCommand(probe))
        }
    }

    func testMissingArgumentsAreRejected() {
        let validator = self.validator(risk: .safe, confirmation: .none, argumentKind: .application)
        XCTAssertThrowsError(try validator.validate(plan(), context: .test())) { error in
            XCTAssertEqual(error as? CommandValidationError, .invalidArguments(probe))
        }
    }

    func testWrongArgumentKindIsRejected() {
        let validator = self.validator(risk: .safe, confirmation: .none, argumentKind: .application)
        let wrong = plan(arguments: .writingMode(.formal))
        XCTAssertThrowsError(try validator.validate(wrong, context: .test())) { error in
            XCTAssertEqual(error as? CommandValidationError, .invalidArguments(probe))
        }
    }

    func testUnexpectedArgumentsAreRejected() {
        let validator = self.validator(risk: .safe, confirmation: .none, argumentKind: .none)
        let wrong = plan(arguments: .application(ApplicationReference(displayName: "Calculator")))
        XCTAssertThrowsError(try validator.validate(wrong, context: .test())) { error in
            XCTAssertEqual(error as? CommandValidationError, .invalidArguments(probe))
        }
    }

    func testEmptyPlanIsRejected() {
        let validator = self.validator(risk: .safe, confirmation: .none)
        XCTAssertThrowsError(try validator.validate(CommandPlan(steps: []), context: .test())) { error in
            XCTAssertEqual(error as? CommandValidationError, .emptyPlan)
        }
    }

    /// Multi-step plans are now fully supported and validated step-by-step.
    func testMultiStepPlanIsValidatedStepByStep() throws {
        let validator = self.validator(risk: .safe, confirmation: .none)
        let multi = CommandPlan(steps: [
            CommandStep(intent: CommandIntent(identifier: probe)),
            CommandStep(intent: CommandIntent(identifier: probe)),
        ])
        let validation = try validator.validate(multi, context: .test())
        XCTAssertEqual(validation, .approved)
    }
}
