import Foundation

/// Unique identity for a confirmation request.
/// Wrapping UUID prevents passing arbitrary strings or mixing up request IDs with command IDs.
struct ConfirmationRequestID: Hashable, Codable, Sendable, CustomStringConvertible {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    var description: String {
        rawValue.uuidString
    }
}

/// Strongly typed representation of a command requiring user approval before execution.
struct ConfirmationRequest: Equatable, Identifiable, Sendable {
    var id: ConfirmationRequestID { requestId }
    let requestId: ConfirmationRequestID
    /// The exact validated plan to execute upon approval.
    let plan: CommandPlan
    /// User-facing title describing the action.
    let title: String
    /// Optional subtitle describing recipient or target entity.
    let subtitle: String?
    /// User-facing description or warning details.
    let details: String
    /// Assessed risk level of the pending action.
    let risk: CommandRisk
    /// Optional preview information (e.g. target application or item).
    let preview: String?
    /// Label for the confirmation action button.
    let confirmActionLabel: String
    /// Label for the cancellation action button.
    let cancelActionLabel: String
    /// When the request was created.
    let createdAt: Date

    init(
        requestId: ConfirmationRequestID = ConfirmationRequestID(),
        plan: CommandPlan,
        title: String,
        subtitle: String? = nil,
        details: String,
        risk: CommandRisk,
        preview: String? = nil,
        confirmActionLabel: String = "Confirm",
        cancelActionLabel: String = "Cancel",
        createdAt: Date = Date()
    ) {
        self.requestId = requestId
        self.plan = plan
        self.title = title
        self.subtitle = subtitle
        self.details = details
        self.risk = risk
        self.preview = preview
        self.confirmActionLabel = confirmActionLabel
        self.cancelActionLabel = cancelActionLabel
        self.createdAt = createdAt
    }
}

/// Explicit decision made by the user.
/// Implicit approval, timeout-based approval, and parser-derived approval are strictly disallowed.
enum ConfirmationDecision: String, Codable, Sendable {
    case confirm
    case cancel
}

/// Result of attempting to resolve a confirmation request.
enum ConfirmationResolution: Equatable, Sendable {
    /// Successfully confirmed; contains the exact pending request to execute.
    case confirmed(ConfirmationRequest)
    /// Explicitly cancelled; no execution may happen.
    case cancelled(ConfirmationRequest)
    /// Resolution was rejected (e.g., stale ID, duplicate resolution, or no pending request).
    case rejected(ConfirmationRejectionReason)
}

/// Reasons why a confirmation resolution was rejected.
enum ConfirmationRejectionReason: String, Codable, Sendable {
    /// The provided ID does not match the currently pending confirmation request.
    case staleId
    /// The confirmation request has already been confirmed or cancelled.
    case alreadyResolved
    /// No confirmation request is currently pending.
    case noPendingRequest
}
