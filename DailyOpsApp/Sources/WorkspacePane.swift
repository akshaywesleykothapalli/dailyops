import SwiftUI

/// Native DailyOps Workspace pane displaying role-aware agent planning, execution states,
/// real runtime activity stages, and interactive role switching.
struct WorkspacePane: View {
    @Bindable var session: AgentSessionController
    @State private var goalInput: String = "Start my workday"

    private let sampleGoals = [
        "Start my workday",
        "Prepare me for tomorrow's review"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsDesign.sectionSpacing) {
                // MARK: - Header
                workspaceHeader

                // MARK: - Unfinished Session (if any)
                unfinishedSessionSection

                // MARK: - Role Selector
                roleSelectorSection

                // MARK: - Quick DailyOps Starter Workflows
                quickDailyOpsSection

                // MARK: - Goal Input
                goalInputSection

                // MARK: - Error Banner (if any)
                if let error = session.error {
                    errorBanner(error)
                }

                // MARK: - Agent Activity Visualization
                if !session.activityStages.isEmpty {
                    activityVisualizationSection
                }

                // MARK: - Plan Display
                if let plan = session.currentPlan, let goal = session.currentGoal {
                    planDisplaySection(plan: plan, goal: goal)
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, SettingsDesign.contentHorizontalMargin)
            .padding(.vertical, SettingsDesign.contentVerticalPadding)
        }
        .background(SettingsDesign.contentBackground)
        .task {
            await session.checkForRestorableSession()
        }
    }

    // MARK: - Header
    private var workspaceHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                DailyOpsBrandMark(size: 28)

                Text("DailyOps")
                    .font(SettingsDesign.editorialTitleFont)
                    .foregroundStyle(Color.primary)
            }

            Text("Goal → Plan → Review → Execute")
                .font(SettingsDesign.bodyFontMedium)
                .foregroundStyle(SettingsDesign.accentBlue)

            Text("DailyOps plans work using your role and always asks before consequential actions.")
                .font(SettingsDesign.captionFont)
                .foregroundStyle(SettingsDesign.secondaryText)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Role Selector
    private var roleSelectorSection: some View {
        WFSection(title: "Active Role") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Select your primary workplace perspective to shape planning priorities:")
                    .font(SettingsDesign.captionFont)
                    .foregroundStyle(SettingsDesign.secondaryText)
                    .padding(.horizontal, SettingsDesign.rowHorizontalPadding)
                    .padding(.top, SettingsDesign.rowVerticalPadding)

                HStack(spacing: 10) {
                    ForEach(EmployeeRole.allCases) { role in
                        rolePill(role)
                    }
                }
                .padding(.horizontal, SettingsDesign.rowHorizontalPadding)
                .padding(.bottom, SettingsDesign.rowVerticalPadding)
            }
        }
    }

    private func rolePill(_ role: EmployeeRole) -> some View {
        let isSelected = session.activeRole == role
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                session.setRole(role)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: iconForRole(role))
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))

                Text(role.displayName)
                    .font(isSelected ? SettingsDesign.bodyFontSemibold : SettingsDesign.bodyFontMedium)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                isSelected ? SettingsDesign.accentBlue : SettingsDesign.controlBackground,
                in: RoundedRectangle(cornerRadius: SettingsDesign.smallCornerRadius)
            )
            .foregroundStyle(isSelected ? Color.white : SettingsDesign.primaryText)
            .overlay {
                RoundedRectangle(cornerRadius: SettingsDesign.smallCornerRadius)
                    .strokeBorder(isSelected ? Color.clear : SettingsDesign.separatorColor, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func iconForRole(_ role: EmployeeRole) -> String {
        switch role {
        case .developer: return "curlybraces"
        case .manager: return "person.3.sequence.fill"
        case .designer: return "paintpalette"
        case .general: return "square.grid.2x2"
        }
    }

    // MARK: - Goal Input
    private var goalInputSection: some View {
        WFSection(title: "Goal Input") {
            VStack(alignment: .leading, spacing: 14) {
                Text("What do you want to accomplish?")
                    .font(SettingsDesign.bodyFontMedium)
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, SettingsDesign.rowHorizontalPadding)
                    .padding(.top, SettingsDesign.rowVerticalPadding)

                HStack(spacing: 10) {
                    TextField("Enter a goal (e.g. Start my workday)", text: $goalInput)
                        .textFieldStyle(.plain)
                        .font(SettingsDesign.bodyFont)
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(SettingsDesign.controlBackground, in: RoundedRectangle(cornerRadius: SettingsDesign.smallCornerRadius))
                        .overlay {
                            RoundedRectangle(cornerRadius: SettingsDesign.smallCornerRadius)
                                .strokeBorder(SettingsDesign.separatorColor, lineWidth: 1)
                        }
                        .onSubmit {
                            submitGoal()
                        }

                    Button {
                        submitGoal()
                    } label: {
                        HStack(spacing: 6) {
                            if session.isProcessing {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            Text("Plan")
                                .font(SettingsDesign.bodyFontSemibold)
                        }
                        .padding(.horizontal, 18)
                        .frame(height: 36)
                        .background(SettingsDesign.accentBlue, in: RoundedRectangle(cornerRadius: SettingsDesign.smallCornerRadius))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(session.isProcessing || goalInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, SettingsDesign.rowHorizontalPadding)

                // Quick sample pills
                HStack(spacing: 8) {
                    Text("Examples:")
                        .font(SettingsDesign.captionFont)
                        .foregroundStyle(SettingsDesign.secondaryText)

                    ForEach(sampleGoals, id: \.self) { sample in
                        Button {
                            goalInput = sample
                            submitGoal()
                        } label: {
                            Text(sample)
                                .font(SettingsDesign.captionFontMedium)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(SettingsDesign.controlBackground, in: Capsule())
                                .overlay {
                                    Capsule().strokeBorder(SettingsDesign.separatorColor, lineWidth: 1)
                                }
                                .foregroundStyle(SettingsDesign.secondaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, SettingsDesign.rowHorizontalPadding)
                .padding(.bottom, SettingsDesign.rowVerticalPadding)
            }
        }
    }

    private func submitGoal() {
        let text = goalInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Task {
            await session.submitGoal(text, source: .text)
        }
    }

    // MARK: - Error Banner
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.red)
            Text(message)
                .font(SettingsDesign.bodyFont)
                .foregroundStyle(Color.red)
            Spacer()
        }
        .padding(12)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: SettingsDesign.smallCornerRadius))
    }

    // MARK: - Activity Visualization
    private var activityVisualizationSection: some View {
        WFSection(title: "Agent Activity") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(session.activityStages) { item in
                    HStack(spacing: 10) {
                        activityItemIcon(for: item.status)

                        Text(item.stage.rawValue)
                            .font(SettingsDesign.bodyFontMedium)
                            .foregroundStyle(SettingsDesign.primaryText)

                        if let detail = item.detail {
                            Text("— \(detail)")
                                .font(SettingsDesign.captionFont)
                                .foregroundStyle(SettingsDesign.secondaryText)
                                .lineLimit(1)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, SettingsDesign.rowHorizontalPadding)
                    .padding(.vertical, 3)
                }
            }
            .padding(.vertical, SettingsDesign.rowVerticalPadding)
        }
    }

    @ViewBuilder
    private func activityItemIcon(for status: ActivityItemStatus) -> some View {
        switch status {
        case .running:
            ProgressView()
                .controlSize(.small)
                .frame(width: 13, height: 13)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.green)
        case .warning:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.orange)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.red)
        case .waiting:
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.orange)
        }
    }

    // MARK: - Plan Display
    private func planDisplaySection(plan: DailyOpsPlan, goal: DailyOpsGoal) -> some View {
        WFSection(title: "Generated Plan") {
            VStack(alignment: .leading, spacing: 16) {
                // Execution Status Header
                executionStatusHeader(plan: plan, goal: goal)

                WFRowDivider()

                // Current Action Card (when running or paused)
                if let currentAction = session.currentAction {
                    currentActionCardSection(action: currentAction)
                    WFRowDivider()
                }

                // Approval Card (if approval requested)
                if session.hasPendingApproval {
                    approvalCardSection
                    WFRowDivider()
                }

                // Execution Controls
                executionControlsSection(plan: plan)

                WFRowDivider()

                // Ordered Tasks List
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("PLAN")
                            .font(SettingsDesign.sectionTitleFont)
                            .foregroundStyle(SettingsDesign.secondaryText)
                            .tracking(0.8)

                        Spacer()

                        let completedCount = plan.tasks.filter { $0.status == .completed }.count
                        Text("\(completedCount) of \(plan.tasks.count) completed")
                            .font(SettingsDesign.captionFont)
                            .foregroundStyle(SettingsDesign.secondaryText)
                    }

                    ForEach(plan.tasks.sorted(by: { $0.order < $1.order })) { task in
                        taskRow(task)
                    }
                }
                .padding(.horizontal, SettingsDesign.rowHorizontalPadding)
                .padding(.bottom, SettingsDesign.rowVerticalPadding)
            }
        }
    }

    // MARK: - Execution Status Header
    private func executionStatusHeader(plan: DailyOpsPlan, goal: DailyOpsGoal) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(goal.originalText.uppercased())
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.primary)

                    if let routing = session.routingDecision {
                        Text(routing.reason)
                            .font(SettingsDesign.captionFont)
                            .foregroundStyle(SettingsDesign.secondaryText)
                    }
                }

                Spacer()

                statusBadge(for: plan.executionState)
            }

            // Compact 4-attribute status row
            HStack(spacing: 8) {
                let completedCount = plan.tasks.filter { $0.status == .completed }.count
                let totalCount = plan.tasks.count

                metaBadge(
                    label: "Status",
                    value: statusText(for: plan.executionState),
                    icon: statusIcon(for: plan.executionState)
                )

                metaBadge(
                    label: "Progress",
                    value: "\(completedCount) / \(totalCount) tasks",
                    icon: "list.number"
                )

                if let routing = session.routingDecision {
                    metaBadge(
                        label: "Intelligence",
                        value: "\(routing.level.rawValue) · \(routing.level.displayName)",
                        icon: "cpu"
                    )
                }

                metaBadge(
                    label: "Role",
                    value: session.activeRole.displayName,
                    icon: iconForRole(session.activeRole)
                )
            }
        }
        .padding(.horizontal, SettingsDesign.rowHorizontalPadding)
        .padding(.top, SettingsDesign.rowVerticalPadding)
    }

    // MARK: - Current Action Card
    private func currentActionCardSection(action: CurrentActionInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("CURRENT ACTION")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(SettingsDesign.accentBlue)
                        .tracking(0.6)
                }

                Spacer()

                Text(action.status)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(SettingsDesign.accentBlue.opacity(0.12), in: Capsule())
                    .foregroundStyle(SettingsDesign.accentBlue)
            }

            Text(action.title)
                .font(SettingsDesign.bodyFontSemibold)
                .foregroundStyle(SettingsDesign.primaryText)

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tool")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(SettingsDesign.secondaryText)
                    Text(action.toolName.isEmpty ? action.toolId : action.toolName)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(SettingsDesign.primaryText)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Permission")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(SettingsDesign.secondaryText)
                    Text(action.permission)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(action.permission == "Safe" ? Color.green : Color.orange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Status")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(SettingsDesign.secondaryText)
                    Text(action.status)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(SettingsDesign.primaryText)
                }
            }
        }
        .padding(12)
        .background(SettingsDesign.controlBackground, in: RoundedRectangle(cornerRadius: SettingsDesign.smallCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: SettingsDesign.smallCornerRadius)
                .strokeBorder(SettingsDesign.accentBlue.opacity(0.35), lineWidth: 1)
        }
        .padding(.horizontal, SettingsDesign.rowHorizontalPadding)
    }

    // MARK: - Task Row
    private func taskRow(_ task: DailyOpsTask) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Task status leading indicator
            taskStatusLeadingIcon(task.status)
                .frame(width: 20, height: 20)
                .padding(.top, 1)

            // Task Title, Description, and Error
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(task.status == .inProgress ? SettingsDesign.bodyFontSemibold : SettingsDesign.bodyFontMedium)
                    .foregroundStyle(SettingsDesign.primaryText)

                if !task.description.isEmpty && task.description != task.title {
                    Text(task.description)
                        .font(SettingsDesign.captionFont)
                        .foregroundStyle(SettingsDesign.secondaryText)
                }

                // If unsupported or failed, display message clearly
                if task.status == .unsupported, let error = task.error {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 10))
                        Text(error)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Color.orange)
                    .padding(.top, 2)
                } else if task.status == .failed, let error = task.error {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 10))
                        Text(error)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Color.red)
                    .padding(.top, 2)
                }

                // Tool requirement badge if specified
                if let toolReq = task.toolRequirement {
                    HStack(spacing: 4) {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.system(size: 9))
                        Text("\(toolReq.toolId) (\(toolReq.riskLevel.rawValue))")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(SettingsDesign.controlBackground, in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(SettingsDesign.secondaryText)
                    .padding(.top, 2)
                }
            }

            Spacer()

            // Task Status Badge
            taskStatusBadge(task.status)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            task.status == .inProgress ? SettingsDesign.accentBlue.opacity(0.06) : SettingsDesign.controlBackground.opacity(0.5),
            in: RoundedRectangle(cornerRadius: SettingsDesign.smallCornerRadius)
        )
        .overlay {
            if task.status == .inProgress {
                RoundedRectangle(cornerRadius: SettingsDesign.smallCornerRadius)
                    .strokeBorder(SettingsDesign.accentBlue.opacity(0.3), lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private func taskStatusLeadingIcon(_ status: TaskStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 14))
                .foregroundStyle(SettingsDesign.secondaryText.opacity(0.6))
        case .inProgress:
            ProgressView()
                .controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.green)
        case .waitingForApproval:
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.orange)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.red)
        case .unsupported:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.orange)
        case .skipped:
            Image(systemName: "forward.fill")
                .font(.system(size: 12))
                .foregroundStyle(SettingsDesign.secondaryText)
        }
    }

    // MARK: - Badges
    private func metaBadge(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(SettingsDesign.accentBlue)

            Text("\(label):")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(SettingsDesign.secondaryText)

            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SettingsDesign.primaryText)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(SettingsDesign.controlBackground, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(SettingsDesign.separatorColor, lineWidth: 1)
        }
    }

    private func statusBadge(for state: PlanExecutionState) -> some View {
        let (text, color, icon) = stateAppearance(state)
        return HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(text)
                .font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12), in: Capsule())
        .foregroundStyle(color)
    }

    private func statusText(for state: PlanExecutionState) -> String {
        switch state {
        case .notStarted: return "Not Started"
        case .inProgress: return "In Progress"
        case .waitingForApproval: return "Waiting Approval"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    private func statusIcon(for state: PlanExecutionState) -> String {
        switch state {
        case .notStarted: return "clock"
        case .inProgress: return "arrow.triangle.2.circlepath"
        case .waitingForApproval: return "hand.raised.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "slash.circle"
        }
    }

    private func stateAppearance(_ state: PlanExecutionState) -> (String, Color, String) {
        switch state {
        case .notStarted: return ("Not Started", .secondary, "clock")
        case .inProgress: return ("In Progress", SettingsDesign.accentBlue, "arrow.triangle.2.circlepath")
        case .waitingForApproval: return ("Waiting Approval", .orange, "hand.raised.fill")
        case .completed: return ("Completed", .green, "checkmark")
        case .failed: return ("Failed", .red, "xmark")
        case .cancelled: return ("Cancelled", .secondary, "slash.circle")
        }
    }

    private func taskStatusBadge(_ status: TaskStatus) -> some View {
        let (text, color, icon) = taskStatusAppearance(status)
        return HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.system(size: 10, weight: .semibold))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
        .foregroundStyle(color)
    }

    private func taskStatusAppearance(_ status: TaskStatus) -> (String, Color, String) {
        switch status {
        case .pending: return ("Pending", .secondary, "clock")
        case .inProgress: return ("Running", SettingsDesign.accentBlue, "arrow.triangle.2.circlepath")
        case .waitingForApproval: return ("Waiting Approval", .orange, "hand.raised.fill")
        case .completed: return ("Completed", .green, "checkmark")
        case .failed: return ("Failed", .red, "xmark")
        case .skipped: return ("Skipped", .secondary, "forward.fill")
        case .unsupported: return ("Unsupported", .orange, "exclamationmark.circle")
        }
    }

    // MARK: - Execution Controls
    private func executionControlsSection(plan: DailyOpsPlan) -> some View {
        HStack(spacing: 12) {
            if session.isExecuting {
                Button {} label: {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Running...")
                            .font(SettingsDesign.bodyFontSemibold)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 36)
                    .background(SettingsDesign.secondaryText.opacity(0.7), in: RoundedRectangle(cornerRadius: SettingsDesign.smallCornerRadius))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(true)
            } else if session.executionState == .waitingForApproval {
                Button {} label: {
                    HStack(spacing: 6) {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Waiting for Approval")
                            .font(SettingsDesign.bodyFontSemibold)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 36)
                    .background(Color.orange.opacity(0.7), in: RoundedRectangle(cornerRadius: SettingsDesign.smallCornerRadius))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(true)
            } else if session.executionState == .completed {
                Button {
                    Task {
                        await session.runAgain()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Run Again")
                            .font(SettingsDesign.bodyFontSemibold)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 36)
                    .background(SettingsDesign.accentBlue, in: RoundedRectangle(cornerRadius: SettingsDesign.smallCornerRadius))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            } else if session.executionState == .failed {
                Button {
                    Task {
                        await session.runAgain()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Retry Plan")
                            .font(SettingsDesign.bodyFontSemibold)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 36)
                    .background(SettingsDesign.accentBlue, in: RoundedRectangle(cornerRadius: SettingsDesign.smallCornerRadius))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    Task {
                        await session.executePlan()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Run Plan")
                            .font(SettingsDesign.bodyFontSemibold)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 36)
                    .background(SettingsDesign.accentBlue, in: RoundedRectangle(cornerRadius: SettingsDesign.smallCornerRadius))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(session.isProcessing)
            }
        }
        .padding(.horizontal, SettingsDesign.rowHorizontalPadding)
    }

    // MARK: - Approval Card
    private var approvalCardSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let request = session.currentApprovalRequest {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.orange)
                        Text("ACTION REQUIRES APPROVAL")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.orange)
                            .tracking(0.6)
                    }

                    Text(request.description.isEmpty ? request.toolName : request.description)
                        .font(SettingsDesign.bodyFontSemibold)
                        .foregroundStyle(Color.primary)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top, spacing: 6) {
                            Text("Reason:")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(SettingsDesign.secondaryText)
                            Text(request.reason)
                                .font(.system(size: 11))
                                .foregroundStyle(SettingsDesign.primaryText)
                        }

                        HStack(spacing: 6) {
                            Text("Risk:")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(SettingsDesign.secondaryText)
                            Text("Confirmation Required")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.orange)
                        }
                    }

                    HStack(spacing: 10) {
                        Spacer()
                        Button("Reject") {
                            Task {
                                await session.rejectCurrentAction()
                            }
                        }
                        .buttonStyle(.plain)
                        .font(SettingsDesign.bodyFontMedium)
                        .padding(.horizontal, 16)
                        .frame(height: 28)
                        .background(SettingsDesign.controlBackground, in: RoundedRectangle(cornerRadius: SettingsDesign.smallCornerRadius))
                        .overlay {
                            RoundedRectangle(cornerRadius: SettingsDesign.smallCornerRadius)
                                .strokeBorder(SettingsDesign.separatorColor, lineWidth: 1)
                        }
                        .foregroundStyle(SettingsDesign.primaryText)

                        Button("Approve") {
                            Task {
                                await session.approveCurrentAction()
                            }
                        }
                        .buttonStyle(.plain)
                        .font(SettingsDesign.bodyFontSemibold)
                        .padding(.horizontal, 16)
                        .frame(height: 28)
                        .background(SettingsDesign.accentBlue, in: RoundedRectangle(cornerRadius: SettingsDesign.smallCornerRadius))
                        .foregroundStyle(.white)
                    }
                }
                .padding(14)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: SettingsDesign.smallCornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: SettingsDesign.smallCornerRadius)
                        .strokeBorder(Color.orange.opacity(0.4), lineWidth: 1)
                }
            }
        }
        .padding(.horizontal, SettingsDesign.rowHorizontalPadding)
    }

    // MARK: - Unfinished Session Section
    @ViewBuilder
    private var unfinishedSessionSection: some View {
        if session.hasRestorableSession, let restored = session.restoredSession {
            WFSection(title: "Unfinished DailyOp") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: "clock.arrow.2.circlepath")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(SettingsDesign.accentBlue)

                                Text("UNFINISHED DAILYOP")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(SettingsDesign.secondaryText)
                            }

                            Text(restored.goalText)
                                .font(SettingsDesign.sectionTitleFont)
                                .foregroundStyle(SettingsDesign.primaryText)

                            let completedCount = restored.tasks.filter { $0.status == .completed }.count
                            let totalCount = restored.tasks.count
                            let timeAgo = formattedTimeAgo(since: restored.updatedAt)

                            Text("\(restored.role.displayName) · \(restored.intelligenceLevel.rawValue)")
                                .font(SettingsDesign.captionFont)
                                .foregroundStyle(SettingsDesign.secondaryText)

                            Text("\(completedCount) of \(totalCount) steps completed")
                                .font(SettingsDesign.captionFont)
                                .foregroundStyle(SettingsDesign.secondaryText)

                            Text(timeAgo)
                                .font(SettingsDesign.captionFont)
                                .foregroundStyle(SettingsDesign.secondaryText)
                        }

                        Spacer()

                        statusPillForAssessment(session.resumeAssessment)
                    }
                    .padding(.horizontal, SettingsDesign.rowHorizontalPadding)
                    .padding(.top, SettingsDesign.rowVerticalPadding)

                    // Specific assessment details
                    assessmentDetailView(for: session.resumeAssessment, restored: restored)
                        .padding(.horizontal, SettingsDesign.rowHorizontalPadding)

                    // Action buttons
                    HStack(spacing: 10) {
                        Button {
                            Task {
                                await session.discardRestorableSession()
                            }
                        } label: {
                            Text("Discard")
                                .font(SettingsDesign.bodyFontMedium)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(SettingsDesign.controlBackground, in: RoundedRectangle(cornerRadius: SettingsDesign.smallCornerRadius))
                                .foregroundStyle(Color.secondary)
                                .overlay {
                                    RoundedRectangle(cornerRadius: SettingsDesign.smallCornerRadius)
                                        .strokeBorder(SettingsDesign.separatorColor, lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Discard restorable session")

                        Spacer()

                        if session.pendingResumeConfirmation != nil || session.resumeAssessment?.disposition == .requiresUserConfirmation {
                            Button {
                                session.cancelRiskyResume()
                            } label: {
                                Text("Cancel")
                                    .font(SettingsDesign.bodyFontMedium)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(SettingsDesign.controlBackground, in: RoundedRectangle(cornerRadius: SettingsDesign.smallCornerRadius))
                                    .foregroundStyle(SettingsDesign.primaryText)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: SettingsDesign.smallCornerRadius)
                                            .strokeBorder(SettingsDesign.separatorColor, lineWidth: 1)
                                    }
                            }
                            .buttonStyle(.plain)

                            Button {
                                Task {
                                    if session.pendingResumeConfirmation == nil {
                                        await session.resumeRestoredSession()
                                    }
                                    await session.confirmRiskyResume()
                                }
                            } label: {
                                Text("Continue")
                                    .font(SettingsDesign.bodyFontSemibold)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 6)
                                    .background(SettingsDesign.accentBlue, in: RoundedRectangle(cornerRadius: SettingsDesign.smallCornerRadius))
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Confirm retry of interrupted action")
                        } else if session.resumeAssessment?.disposition == .safeToContinue || session.resumeAssessment?.disposition == .requiresPendingApproval {
                            Button {
                                Task {
                                    await session.resumeRestoredSession()
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    if session.isResuming {
                                        ProgressView().controlSize(.small)
                                    }
                                    Text("Resume")
                                        .font(SettingsDesign.bodyFontSemibold)
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 6)
                                .background(SettingsDesign.accentBlue, in: RoundedRectangle(cornerRadius: SettingsDesign.smallCornerRadius))
                                .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                            .disabled(session.isResuming || session.isProcessing)
                            .accessibilityLabel("Resume unfinished session")
                        }
                    }
                    .padding(.horizontal, SettingsDesign.rowHorizontalPadding)
                    .padding(.bottom, SettingsDesign.rowVerticalPadding)
                }
            }
        }
    }

    private func formattedTimeAgo(since date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Interrupted " + formatter.localizedString(for: date, relativeTo: Date())
    }

    @ViewBuilder
    private func statusPillForAssessment(_ assessment: ResumeAssessment?) -> some View {
        let (title, bg, fg): (String, Color, Color) = {
            guard let disposition = assessment?.disposition else {
                return ("Ready", Color.blue.opacity(0.12), SettingsDesign.accentBlue)
            }
            switch disposition {
            case .safeToContinue:
                return ("Ready to continue", Color.green.opacity(0.12), Color.green)
            case .requiresPendingApproval:
                return ("Action Requires Approval", Color.orange.opacity(0.12), Color.orange)
            case .requiresUserConfirmation:
                return ("Confirmation Required", Color.yellow.opacity(0.15), Color.orange)
            case .manualReviewRequired:
                return ("Manual Review Required", Color.red.opacity(0.12), Color.red)
            case .notResumable:
                return ("Not Resumable", Color.secondary.opacity(0.12), Color.secondary)
            }
        }()

        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(bg, in: Capsule())
            .foregroundStyle(fg)
    }

    @ViewBuilder
    private func assessmentDetailView(for assessment: ResumeAssessment?, restored: RestoredAgentSession) -> some View {
        if let confirmation = session.pendingResumeConfirmation {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 14))

                VStack(alignment: .leading, spacing: 3) {
                    Text("RETRY ACTION?")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.orange)

                    Text("DailyOps was interrupted while this action may have been changing data.")
                        .font(SettingsDesign.captionFont)
                        .foregroundStyle(SettingsDesign.secondaryText)

                    Text(confirmation.taskTitle)
                        .font(SettingsDesign.bodyFontSemibold)
                        .foregroundStyle(SettingsDesign.primaryText)

                    Text("Retrying could repeat the action.")
                        .font(SettingsDesign.captionFont)
                        .foregroundStyle(SettingsDesign.secondaryText)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: SettingsDesign.smallCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: SettingsDesign.smallCornerRadius)
                    .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
            }
        } else if let assessment = assessment {
            switch assessment.disposition {
            case .safeToContinue:
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Ready to continue")
                        .font(SettingsDesign.captionFontMedium)
                        .foregroundStyle(SettingsDesign.primaryText)
                }

            case .requiresPendingApproval:
                let actionName = restored.pendingApproval?.toolName ?? assessment.interruptedTaskTitle ?? "Pending Action"
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 14))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("ACTION REQUIRES APPROVAL")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.orange)

                        Text(actionName)
                            .font(SettingsDesign.bodyFontSemibold)
                            .foregroundStyle(SettingsDesign.primaryText)

                        Text("DailyOps cannot continue until this action is reviewed.")
                            .font(SettingsDesign.captionFont)
                            .foregroundStyle(SettingsDesign.secondaryText)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: SettingsDesign.smallCornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: SettingsDesign.smallCornerRadius)
                        .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
                }

            case .requiresUserConfirmation:
                let taskName = assessment.interruptedTaskTitle ?? "interrupted action"
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 14))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("RETRY ACTION?")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.orange)

                        Text("DailyOps was interrupted while this action may have been changing data.")
                            .font(SettingsDesign.captionFont)
                            .foregroundStyle(SettingsDesign.secondaryText)

                        Text(taskName)
                            .font(SettingsDesign.bodyFontSemibold)
                            .foregroundStyle(SettingsDesign.primaryText)

                        Text("Retrying could repeat the action.")
                            .font(SettingsDesign.captionFont)
                            .foregroundStyle(SettingsDesign.secondaryText)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: SettingsDesign.smallCornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: SettingsDesign.smallCornerRadius)
                        .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
                }

            case .manualReviewRequired:
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "hand.raised.fill")
                        .foregroundStyle(.red)
                        .font(.system(size: 14))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("MANUAL REVIEW REQUIRED")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.red)

                        Text(assessment.reason)
                            .font(SettingsDesign.captionFont)
                            .foregroundStyle(SettingsDesign.secondaryText)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: SettingsDesign.smallCornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: SettingsDesign.smallCornerRadius)
                        .strokeBorder(Color.red.opacity(0.3), lineWidth: 1)
                }

            case .notResumable:
                HStack(spacing: 6) {
                    Image(systemName: "nosign")
                        .foregroundStyle(.secondary)
                    Text("This DailyOp cannot be resumed safely.")
                        .font(SettingsDesign.captionFont)
                        .foregroundStyle(SettingsDesign.secondaryText)
                }
            }
        }
    }

    // MARK: - Quick DailyOps
    private var quickDailyOpsSection: some View {
        WFSection(title: "Quick DailyOps") {
            VStack(alignment: .leading, spacing: 14) {
                let recommended = PredefinedDailyOpsCatalog.recommended(for: session.activeRole)
                let more = PredefinedDailyOpsCatalog.other(for: session.activeRole)

                Text("Recommended for \(session.activeRole.displayName)")
                    .font(SettingsDesign.bodyFontMedium)
                    .foregroundStyle(SettingsDesign.primaryText)
                    .padding(.horizontal, SettingsDesign.rowHorizontalPadding)
                    .padding(.top, SettingsDesign.rowVerticalPadding)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 10)], spacing: 10) {
                    ForEach(recommended) { op in
                        predefinedOpCard(op)
                    }
                }
                .padding(.horizontal, SettingsDesign.rowHorizontalPadding)

                if !more.isEmpty {
                    Text("More DailyOps")
                        .font(SettingsDesign.bodyFontMedium)
                        .foregroundStyle(SettingsDesign.secondaryText)
                        .padding(.horizontal, SettingsDesign.rowHorizontalPadding)
                        .padding(.top, 4)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 10)], spacing: 10) {
                        ForEach(more) { op in
                            predefinedOpCard(op)
                        }
                    }
                    .padding(.horizontal, SettingsDesign.rowHorizontalPadding)
                }
            }
            .padding(.bottom, SettingsDesign.rowVerticalPadding)
        }
    }

    private func predefinedOpCard(_ op: PredefinedDailyOp) -> some View {
        Button {
            goalInput = op.suggestedGoalText
            Task {
                _ = await session.submitGoal(op.suggestedGoalText)
            }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: op.iconName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SettingsDesign.accentBlue)

                    Text(op.title)
                        .font(SettingsDesign.bodyFontSemibold)
                        .foregroundStyle(SettingsDesign.primaryText)
                        .lineLimit(1)
                }

                Text(op.shortDescription)
                    .font(SettingsDesign.captionFont)
                    .foregroundStyle(SettingsDesign.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SettingsDesign.controlBackground, in: RoundedRectangle(cornerRadius: SettingsDesign.smallCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: SettingsDesign.smallCornerRadius)
                    .strokeBorder(SettingsDesign.separatorColor, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(op.title)
        .accessibilityHint("Plans '\(op.suggestedGoalText)'")
    }
}

/// Appearance-aware DailyOps brand mark component.
struct DailyOpsBrandMark: View {
    @Environment(\.colorScheme) private var colorScheme
    var size: CGFloat = 28

    var body: some View {
        let name = colorScheme == .dark ? "DailyOps-Dark" : "DailyOps-Light"
        let nsImage: NSImage? = {
            if let img = NSImage(named: NSImage.Name(name)) {
                return img
            }
            if let path = Bundle.main.path(forResource: name, ofType: "png") {
                return NSImage(contentsOfFile: path)
            }
            if let url = Bundle.main.url(forResource: name, withExtension: "png") {
                return NSImage(contentsOf: url)
            }
            let projectPath = "/Users/akshaywesley/Desktop/DailyOps/Branding/\(name).png"
            if FileManager.default.fileExists(atPath: projectPath) {
                return NSImage(contentsOfFile: projectPath)
            }
            return nil
        }()

        if let nsImage = nsImage {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        } else {
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.7, weight: .semibold))
                .foregroundStyle(SettingsDesign.accentBlue)
        }
    }
}

