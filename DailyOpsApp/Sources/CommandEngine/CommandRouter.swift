import Foundation

/// Sequences the engine: parse, validate, then dispatch to exactly one
/// executor. Nothing else in the app calls an executor directly, so this is
/// the only path from a transcript to a side effect.
@MainActor
struct CommandRouter {
    private let parsers: [CommandParsing]
    private let validator: CommandValidator
    private let executors: [CommandExecuting]
    let confirmationManager: ConfirmationManaging

    /// Parsers are tried in order and the first plan wins.
    init(
        parsers: [CommandParsing],
        validator: CommandValidator,
        executors: [CommandExecuting],
        confirmationManager: ConfirmationManaging = ConfirmationManager()
    ) {
        self.parsers = parsers
        self.validator = validator
        self.executors = executors
        self.confirmationManager = confirmationManager
    }

    /// Exposes the currently pending confirmation request, if any.
    var pendingConfirmation: ConfirmationRequest? {
        confirmationManager.pendingConfirmation
    }

    /// A transcript that is not a recognised command returns `.ignored`, and
    /// the caller is responsible for continuing with normal dictation.
    func handle(_ transcript: String, context: CommandContext) -> CommandResult {
        guard let plan = firstPlan(for: transcript, context: context) else {
            return .ignored
        }
        return run(plan, context: context)
    }

    /// Asynchronously handles a transcript through the deterministic command parsers.
    /// If not recognized deterministically, returns `.ignored` to fall back to normal dictation.
    func handleAsync(_ transcript: String, context: CommandContext) async -> CommandResult {
        handle(transcript, context: context)
    }

    /// Runs an already-parsed plan. If any step requires confirmation, safe steps prior
    /// to it execute, and execution halts at the confirmation boundary.
    func run(_ plan: CommandPlan, context: CommandContext) -> CommandResult {
        let resolvedPlan = validator.resolve(plan)
        do {
            _ = try validator.validate(resolvedPlan, context: context)
        } catch let error as CommandValidationError {
            return failure(for: error)
        } catch {
            return .failure(message: error.localizedDescription)
        }

        return executeSequence(
            steps: resolvedPlan.steps,
            totalPlanCount: resolvedPlan.steps.count,
            isApprovedStart: false,
            context: context
        )
    }

    /// Confirms a pending confirmation request by ID and executes the exact previously validated plan.
    /// Rejects stale, already-resolved, or missing requests without executing.
    func confirm(id: ConfirmationRequestID, context: CommandContext) -> CommandResult {
        let resolution = confirmationManager.resolve(id: id, decision: .confirm)
        switch resolution {
        case .confirmed(let request):
            return executeApproved(plan: request.plan, context: context)
        case .cancelled:
            return .failure(message: "Confirmation was cancelled.")
        case .rejected(let reason):
            switch reason {
            case .staleId:
                return .failure(message: "Confirmation request is stale.")
            case .alreadyResolved:
                return .failure(message: "Confirmation request has already been resolved.")
            case .noPendingRequest:
                return .failure(message: "No pending confirmation request.")
            }
        }
    }

    /// Cancels a pending confirmation request by ID without executing anything.
    @discardableResult
    func cancel(id: ConfirmationRequestID) -> CommandResult {
        let resolution = confirmationManager.resolve(id: id, decision: .cancel)
        switch resolution {
        case .cancelled:
            return .success(message: "Cancelled")
        case .confirmed:
            return .failure(message: "Already confirmed.")
        case .rejected(let reason):
            switch reason {
            case .staleId:
                return .failure(message: "Confirmation request is stale.")
            case .alreadyResolved:
                return .failure(message: "Confirmation request has already been resolved.")
            case .noPendingRequest:
                return .failure(message: "No pending confirmation request.")
            }
        }
    }

    /// Directly executes an approved plan's steps sequentially.
    private func executeApproved(plan: CommandPlan, context: CommandContext) -> CommandResult {
        executeSequence(
            steps: plan.steps,
            totalPlanCount: plan.steps.count,
            isApprovedStart: true,
            context: context
        )
    }

    private func executeSequence(
        steps: [CommandStep],
        totalPlanCount: Int,
        isApprovedStart: Bool,
        context: CommandContext
    ) -> CommandResult {
        guard !steps.isEmpty else {
            return failure(for: CommandValidationError.emptyPlan)
        }

        var completedFeedback: [String] = []

        for (offset, step) in steps.enumerated() {
            let intent = step.intent
            let stepIndex = totalPlanCount - steps.count + offset
            let definition = validator.definition(for: intent.identifier)
                ?? CommandDefinition(
                    identifier: intent.identifier,
                    name: "Command",
                    risk: .safe,
                    confirmation: .none
                )

            let isApprovedStep = (offset == 0 && isApprovedStart)
            let stepRequiresConfirmation = requiresConfirmation(definition: definition)

            if stepRequiresConfirmation && !isApprovedStep {
                let remainingSteps = Array(steps[offset...])
                let remainingPlan = CommandPlan(steps: remainingSteps)
                let reason = "\(definition.name) needs your approval."
                confirmationManager.requestConfirmation(
                    for: remainingPlan,
                    definition: definition,
                    context: context,
                    reason: reason
                )
                return .confirmationRequired(plan: remainingPlan, message: reason)
            }

            guard let executor = executors.first(where: { $0.supportedIdentifiers.contains(intent.identifier) }) else {
                let msg = "\(intent.identifier.rawValue) is not available."
                return formatFailure(
                    errorMsg: msg,
                    completedCount: completedFeedback.count,
                    stepNumber: stepIndex + 1,
                    totalCount: totalPlanCount
                )
            }

            do {
                let feedback = try executor.execute(intent, context: context)
                completedFeedback.append(feedback)
            } catch let error as CommandExecutionError {
                let msg = failureMessage(for: error)
                return formatFailure(
                    errorMsg: msg,
                    completedCount: completedFeedback.count,
                    stepNumber: stepIndex + 1,
                    totalCount: totalPlanCount
                )
            } catch {
                return formatFailure(
                    errorMsg: error.localizedDescription,
                    completedCount: completedFeedback.count,
                    stepNumber: stepIndex + 1,
                    totalCount: totalPlanCount
                )
            }
        }

        if totalPlanCount > 1 {
            return .success(message: "Completed \(totalPlanCount) actions: \(completedFeedback.joined(separator: ", "))")
        } else {
            return .success(message: completedFeedback.first ?? "Done")
        }
    }

    private func requiresConfirmation(definition: CommandDefinition) -> Bool {
        switch (definition.risk, definition.confirmation) {
        case (_, .mandatory):
            return true
        case (.destructive, _):
            return true
        case (.sensitive, .optional):
            return true
        case (.sensitive, .none), (.safe, _):
            return false
        }
    }

    private func formatFailure(
        errorMsg: String,
        completedCount: Int,
        stepNumber: Int,
        totalCount: Int
    ) -> CommandResult {
        if totalCount > 1 {
            if completedCount > 0 {
                return .failure(message: "Completed \(completedCount) of \(totalCount) actions. Step \(stepNumber) failed: \(errorMsg)")
            } else {
                return .failure(message: "Step \(stepNumber) failed: \(errorMsg)")
            }
        } else {
            return .failure(message: errorMsg)
        }
    }

    private func failureMessage(for error: CommandExecutionError) -> String {
        switch error {
        case .unsupported(let identifier):
            return "\(identifier.rawValue) is not available."
        case .malformedArguments(let identifier):
            return "\(identifier.rawValue) was given unexpected details."
        case .operationFailed(let message):
            return message
        }
    }

    private func firstPlan(for transcript: String, context: CommandContext) -> CommandPlan? {
        for parser in parsers {
            if let plan = parser.parse(transcript, context: context) {
                return plan
            }
        }
        return nil
    }

    private func failure(for error: CommandValidationError) -> CommandResult {
        switch error {
        case .unknownCommand(let identifier):
            .failure(message: "\(identifier.rawValue) is not a known command.")
        case .invalidArguments(let identifier):
            .failure(message: "\(identifier.rawValue) was given unexpected details.")
        case .emptyPlan:
            .failure(message: "Nothing to run.")
        case .multiStepNotSupported:
            .failure(message: "Multi-step commands are not supported yet.")
        case .ambiguousRecipient(let query, let matches):
            .failure(message: "Multiple contacts found for '\(query)' (\(matches.joined(separator: ", "))). Please specify full name.")
        case .recipientNotFound(let query):
            .failure(message: "No contact found for '\(query)'.")
        case .contactsUnavailable(let reason):
            .failure(message: "Contacts unavailable: \(reason)")
        }
    }

    private func failure(for error: CommandExecutionError) -> CommandResult {
        switch error {
        case .unsupported(let identifier):
            .failure(message: "\(identifier.rawValue) is not available.")
        case .malformedArguments(let identifier):
            .failure(message: "\(identifier.rawValue) was given unexpected details.")
        case .operationFailed(let message):
            .failure(message: message)
        }
    }
}
