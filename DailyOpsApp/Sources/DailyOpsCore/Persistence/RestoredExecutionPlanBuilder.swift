import Foundation

/// Validates and constructs an executable DailyOpsPlan from a persisted AgentSessionSnapshot.
/// Preserves completed, unsupported, and skipped states, exact tool requirements, parameters,
/// and validates dependency relationships before execution resumption.
public enum RestoredExecutionPlanBuilder {

    public enum BuildError: LocalizedError, Equatable {
        case invalidTaskDependencies(String)
        case missingToolParameters(String)
        case unresolvableState(String)

        public var errorDescription: String? {
            switch self {
            case .invalidTaskDependencies(let msg): return "Invalid dependencies: \(msg)"
            case .missingToolParameters(let msg): return "Missing tool parameters: \(msg)"
            case .unresolvableState(let msg): return "Unresolvable state: \(msg)"
            }
        }
    }

    /// Reconstructs a DailyOpsPlan from a snapshot for explicit resumption.
    /// Does not mutate the persisted snapshot.
    public static func build(from snapshot: AgentSessionSnapshot) throws -> DailyOpsPlan {
        let taskIDs = Set(snapshot.tasks.map { $0.taskID })

        // Validate dependencies
        for task in snapshot.tasks {
            for dep in task.dependencies {
                guard taskIDs.contains(dep) else {
                    throw BuildError.invalidTaskDependencies("Task '\(task.title)' depends on non-existent task \(dep)")
                }
            }
        }

        let sortedTaskSnapshots = snapshot.tasks.sorted { $0.order < $1.order }
        var reconstructedTasks: [DailyOpsTask] = []

        for taskSnapshot in sortedTaskSnapshots {
            let taskStatus: TaskStatus
            var taskResult: TaskResult? = nil
            var taskError: String? = nil

            switch taskSnapshot.status {
            case .completed:
                taskStatus = .completed
                taskResult = taskSnapshot.resultSummary.map { TaskResult(success: true, output: $0) }
            case .unsupported:
                taskStatus = .unsupported
                taskError = taskSnapshot.error
            case .skipped:
                taskStatus = .skipped
                taskError = taskSnapshot.error
            case .pending, .inProgress, .waitingForApproval:
                // Normalizes interrupted or waiting tasks back to pending for execution engine
                taskStatus = .pending
            case .failed:
                throw BuildError.unresolvableState("Failed task '\(taskSnapshot.title)' cannot be automatically resumed.")
            }

            var toolRequirement: ToolRequirement? = nil
            if let toolId = taskSnapshot.toolID {
                let riskLevel = mapRiskLevel(taskSnapshot.riskLevel)
                let params = taskSnapshot.parameters ?? [:]
                toolRequirement = ToolRequirement(
                    toolId: toolId,
                    riskLevel: riskLevel,
                    parameters: params
                )
            }

            let task = DailyOpsTask(
                id: taskSnapshot.taskID,
                title: taskSnapshot.title,
                description: taskSnapshot.description,
                order: taskSnapshot.order,
                status: taskStatus,
                toolRequirement: toolRequirement,
                dependencies: taskSnapshot.dependencies,
                result: taskResult,
                error: taskError
            )
            reconstructedTasks.append(task)
        }

        return DailyOpsPlan(
            id: snapshot.planID,
            goalID: snapshot.goalID,
            tasks: reconstructedTasks,
            createdAt: snapshot.createdAt,
            executionState: .notStarted
        )
    }

    private static func mapRiskLevel(_ risk: PersistedRiskLevel?) -> ActionRiskLevel {
        switch risk {
        case .safe: return .safe
        case .confirmationRequired: return .confirmationRequired
        case .critical: return .critical
        case .none: return .safe
        }
    }
}
