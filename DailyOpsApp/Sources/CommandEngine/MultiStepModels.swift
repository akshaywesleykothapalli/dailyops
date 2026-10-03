import Foundation

/// Status of executing an individual step in a command plan.
enum StepExecutionStatus: String, Codable, Sendable {
    case completed
    case failed
    case skipped
    case pendingConfirmation
}

/// Record of an individual step's execution attempt and feedback.
struct StepExecutionRecord: Equatable, Codable, Sendable {
    let stepIndex: Int
    let intent: CommandIntent
    let status: StepExecutionStatus
    let message: String?

    init(stepIndex: Int, intent: CommandIntent, status: StepExecutionStatus, message: String? = nil) {
        self.stepIndex = stepIndex
        self.intent = intent
        self.status = status
        self.message = message
    }
}

/// Overall outcome status for a multi-step plan.
enum MultiStepStatus: String, Codable, Sendable {
    case completed
    case failed
    case cancelled
    case confirmationRequired
    case partiallyCompleted
}

/// Comprehensive structured result of executing a multi-step command plan.
struct MultiStepExecutionResult: Equatable, Sendable {
    let plan: CommandPlan
    let status: MultiStepStatus
    let completedSteps: [StepExecutionRecord]
    let failedStep: StepExecutionRecord?
    let skippedSteps: [CommandStep]
    let summaryMessage: String

    init(
        plan: CommandPlan,
        status: MultiStepStatus,
        completedSteps: [StepExecutionRecord],
        failedStep: StepExecutionRecord? = nil,
        skippedSteps: [CommandStep] = [],
        summaryMessage: String
    ) {
        self.plan = plan
        self.status = status
        self.completedSteps = completedSteps
        self.failedStep = failedStep
        self.skippedSteps = skippedSteps
        self.summaryMessage = summaryMessage
    }
}
