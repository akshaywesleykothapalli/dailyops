import Foundation

/// Deterministic policy engine that assesses whether and how a persisted agent session may resume.
/// Evaluates safety, idempotency, risk levels, and integrity constraints without initiating execution.
public enum AgentSessionResumePolicy {

    private static let safeIdempotentTools: Set<String> = [
        "open_application",
        "get_current_time",
        "system_status"
    ]

    /// Evaluates a persisted session snapshot and returns a deterministic ResumeAssessment.
    public static func evaluate(_ snapshot: AgentSessionSnapshot) -> ResumeAssessment {
        // 1. Schema version validation
        guard snapshot.schemaVersion <= AgentSessionSnapshot.currentSchemaVersion else {
            return ResumeAssessment(
                disposition: .manualReviewRequired,
                reason: "Unsupported schema version \(snapshot.schemaVersion)"
            )
        }

        // 1b. Check for legacy v1 or missing parameters on tasks that need execution
        for task in snapshot.tasks {
            if task.status != .completed && task.status != .unsupported && task.status != .skipped {
                if task.toolID != nil && task.parameters == nil {
                    return ResumeAssessment(
                        disposition: .manualReviewRequired,
                        reason: "Legacy snapshot task '\(task.title)' lacks tool parameters: manual review required."
                    )
                }
            }
        }

        // 2. Structural consistency checks
        let knownTaskIDs = Set(snapshot.tasks.map { $0.taskID })
        for task in snapshot.tasks {
            for dep in task.dependencies {
                if !knownTaskIDs.contains(dep) {
                    return ResumeAssessment(
                        disposition: .manualReviewRequired,
                        reason: "Invalid task dependency reference in plan"
                    )
                }
            }
        }

        if let approval = snapshot.pendingApproval {
            if !knownTaskIDs.contains(approval.taskID) {
                return ResumeAssessment(
                    disposition: .manualReviewRequired,
                    reason: "Pending approval references non-existent task"
                )
            }
        }

        // 3. Terminal session statuses
        if snapshot.status == .completed || snapshot.status == .cancelled {
            return ResumeAssessment(
                disposition: .notResumable,
                reason: "Session is in terminal state '\(snapshot.status.rawValue)'."
            )
        }

        // 4. Failed task or failed status
        if snapshot.status == .failed || snapshot.tasks.contains(where: { $0.status == .failed }) {
            return ResumeAssessment(
                disposition: .manualReviewRequired,
                reason: "Task execution failed: manual review required."
            )
        }

        // 5. Unsupported task check
        if snapshot.tasks.contains(where: { $0.status == .unsupported }) {
            return ResumeAssessment(
                disposition: .manualReviewRequired,
                reason: "Required integration is unsupported or disconnected: manual review required."
            )
        }

        // 6. Planned status
        if snapshot.status == .planned {
            return ResumeAssessment(
                disposition: .safeToContinue,
                reason: "Plan has not started execution."
            )
        }

        // 7. Waiting for approval status
        if snapshot.status == .waitingForApproval {
            if let approval = snapshot.pendingApproval {
                return ResumeAssessment(
                    disposition: .requiresPendingApproval,
                    reason: "Action requires explicit approval before continuation: \(approval.toolName)",
                    interruptedTaskID: approval.taskID,
                    pendingApproval: approval
                )
            } else {
                return ResumeAssessment(
                    disposition: .manualReviewRequired,
                    reason: "Session marked as waiting for approval but no pending approval request found."
                )
            }
        }

        // 8. Interrupted execution (.executing or .paused)
        let interrupted = snapshot.tasks.first(where: { $0.status == .inProgress || $0.status == .waitingForApproval })
            ?? snapshot.tasks.first(where: { $0.status == .pending })

        if let task = interrupted {
            // Critical action check
            if task.riskLevel == .critical {
                return ResumeAssessment(
                    disposition: .requiresUserConfirmation,
                    reason: "Critical actions require explicit confirmation and cannot be automatically resumed.",
                    interruptedTaskID: task.taskID,
                    interruptedTaskTitle: task.title
                )
            }

            // Safe + Idempotent check
            if isSafeAndIdempotent(task) {
                return ResumeAssessment(
                    disposition: .safeToContinue,
                    reason: "Interrupted task '\(task.title)' is idempotent and safe to continue.",
                    interruptedTaskID: task.taskID,
                    interruptedTaskTitle: task.title
                )
            }

            // Mutating action check
            return ResumeAssessment(
                disposition: .requiresUserConfirmation,
                reason: "Interrupted action '\(task.title)' may have mutated persistent state: user confirmation required.",
                interruptedTaskID: task.taskID,
                interruptedTaskTitle: task.title
            )
        }

        // All tasks completed
        return ResumeAssessment(
            disposition: .notResumable,
            reason: "All tasks in session have already completed."
        )
    }

    private static func isSafeAndIdempotent(_ task: PersistedTaskSnapshot) -> Bool {
        if task.riskLevel == .safe {
            if let toolID = task.toolID {
                return safeIdempotentTools.contains(toolID)
            }
            return true
        }
        return false
    }
}
