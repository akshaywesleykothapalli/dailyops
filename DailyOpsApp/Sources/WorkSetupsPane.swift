import SwiftUI
import AppKit

struct WorkSetupsPane: View {
    @State private var profiles = RoleWorkspaceStore.shared.load()
    @State private var selectedRole: EmployeeRole = .developer
    @State private var saveError: String?
    private var index: Int { profiles.firstIndex { $0.role == selectedRole } ?? 0 }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsDesign.sectionSpacing) {
                Text("Work Setups").font(SettingsDesign.editorialTitleFont)
                Text("Enable Command Mode, hold your configured talk key, and say “open my work setup”. Apps are opened in order; unavailable apps are reported in Agent Activity.").foregroundStyle(.secondary)
                Picker("Role", selection: $selectedRole) {
                    ForEach(EmployeeRole.allCases) { role in Text(role.displayName).tag(role) }
                }.pickerStyle(.segmented)
                WFSection(title: "Workspace") {
                    TextField("Workflow name", text: $profiles[index].workflowName)
                    TextField("Custom voice phrase", text: Binding(get: { profiles[index].voicePhrases.first ?? "" }, set: { profiles[index].voicePhrases = $0.isEmpty ? [] : [$0] }))
                    HStack {
                        TextField("Default project / folder", text: $profiles[index].defaultProjectPath)
                        Button("Choose…") {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true; panel.canChooseFiles = false
                            if panel.runModal() == .OK, let url = panel.url { profiles[index].defaultProjectPath = url.path }
                        }
                    }
                    TextField("Project editor (blank uses Finder)", text: $profiles[index].projectEditor)
                }
                WFSection(title: "Ordered steps") {
                    ForEach(profiles[index].workflow.steps.indices, id: \.self) { step in
                        HStack {
                            Toggle("", isOn: $profiles[index].workflow.steps[step].enabled).labelsHidden()
                            Picker("Action", selection: $profiles[index].workflow.steps[step].kind) {
                                ForEach(RoleWorkflowStep.Kind.allCases, id: \.self) { kind in Text(kind.rawValue).tag(kind) }
                            }.frame(width: 125)
                            TextField("App, folder or URL", text: $profiles[index].workflow.steps[step].value)
                            if profiles[index].workflow.steps[step].kind == .application {
                                Text(NSWorkspace.shared.fullPath(forApplication: profiles[index].workflow.steps[step].value) == nil ? "Unavailable" : "Installed").font(.caption).foregroundStyle(.secondary)
                            }
                            Button { profiles[index].workflow.steps.swapAt(step, step - 1) } label: { Image(systemName: "arrow.up") }.disabled(step == 0)
                            Button { profiles[index].workflow.steps.swapAt(step, step + 1) } label: { Image(systemName: "arrow.down") }.disabled(step + 1 == profiles[index].workflow.steps.count)
                            Button { profiles[index].workflow.steps.remove(at: step) } label: { Image(systemName: "minus.circle") }
                        }
                    }
                    Button("Add step") { profiles[index].workflow.steps.append(.init(kind: .application, value: "")) }
                }
                HStack {
                    Button("Save setup") {
                        do { try RoleWorkspaceStore.shared.save(profiles); saveError = nil } catch { saveError = error.localizedDescription }
                    }.buttonStyle(.borderedProminent)
                    Button("Reset this role") { profiles[index] = .defaults(selectedRole) }
                    Text("Changes take effect after saving.").font(.caption).foregroundStyle(.secondary)
                }
                if let saveError { Text(saveError).foregroundStyle(.red) }
            }.padding(.horizontal, SettingsDesign.contentHorizontalMargin).padding(.vertical, SettingsDesign.contentVerticalPadding)
        }.background(SettingsDesign.contentBackground)
    }
}
