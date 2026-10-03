import Foundation

public protocol DailyOpsTool: Sendable {
    var id: String { get }
    var name: String { get }
    var description: String { get }
    var category: ToolCategory { get }
    var riskLevel: ActionRiskLevel { get }
    func execute(parameters: [String: String]) async throws -> ToolResult
}

public struct ToolResult: Sendable, Codable {
    public let success: Bool
    public let output: String?
    public let error: String?

    public init(success: Bool, output: String? = nil, error: String? = nil) {
        self.success = success
        self.output = output
        self.error = error
    }
}