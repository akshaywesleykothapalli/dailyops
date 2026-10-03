import SwiftUI

struct CommandModePane: View {
    @AppStorage("commandModeEnabled") private var isEnabled = true
    @ObservedObject private var customStore = CustomCommandStore.shared

    @State private var editingCommand: CustomCommand? = nil
    @State private var isCreatingCommand = false
    @State private var testFeedback: (commandId: UUID, message: String, isSuccess: Bool)? = nil

    private let registry = CommandRegistry.standard()

    private var groups: [CommandGroup] {
        func group(title: String, ids: [CommandIdentifier]) -> CommandGroup {
            CommandGroup(
                id: title,
                title: title,
                commands: ids.compactMap { registry.definition(for: $0) }
            )
        }

        return [
            group(title: "Apps", ids: [
                .appOpen, .appQuit, .appHide, .appSwitch
            ]),
            group(title: "Settings & History", ids: [
                .settingsOpen, .historyOpen
            ]),
            group(title: "Clipboard", ids: [
                .clipboardCopyLast, .clipboardClear, .clipboardInspect
            ]),
            group(title: "Speech", ids: [
                .dictationModeFormal, .dictationModeStandard, .speechModelReload
            ]),
            group(title: "Browser", ids: [
                .browserOpenURL, .browserSearch, .browserOpenDefault, .browserOpenPrivate
            ]),
            group(title: "WhatsApp", ids: [
                .whatsAppOpenChat, .whatsAppSendMessage
            ]),
            group(title: "Calendar", ids: [
                .calendarOpen, .calendarListEvents, .calendarCreateEvent, .calendarDeleteEvent
            ]),
            group(title: "Reminders", ids: [
                .remindersOpen, .remindersList, .remindersCreate, .remindersComplete, .remindersDelete
            ]),
            group(title: "Notes", ids: [
                .notesOpen, .notesCreate, .notesFind, .notesOpenNote
            ]),
            group(title: "Finder & Files", ids: [
                .finderOpenLocation, .finderFindFiles, .finderCreateFolder, .finderCreateFile,
                .finderReveal, .finderTrash, .finderRename, .finderDuplicate
            ]),
            group(title: "System — Audio", ids: [
                .systemVolumeUp, .systemVolumeDown, .systemVolumeSet, .systemVolumeMute,
                .systemVolumeUnmute, .systemVolumeGet
            ]),
            group(title: "System — Power & Session", ids: [
                .systemSleep, .systemLock, .systemLogout, .systemRestart, .systemShutdown
            ]),
            group(title: "System — Information", ids: [
                .systemBattery, .systemMacOSVersion, .systemTime, .systemDate
            ]),
            group(title: "Context", ids: [
                .contextOpen, .contextMessage, .contextCheck
            ]),
            group(title: "Contacts", ids: [
                .contactsFind, .contactsShow
            ]),
            group(title: "Mail", ids: [
                .mailOpen, .mailCompose
            ]),
        ].filter { !$0.commands.isEmpty }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Master Toggle
                WFSection {
                    WFToggleRow(
                        "Enable Voice Commands",
                        description: "Recognize system, application, and file voice commands during dictation",
                        isOn: $isEnabled
                    )
                }
                .padding(.horizontal, SettingsDesign.contentHorizontalMargin)

                // Custom Commands Section
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        HStack(spacing: 8) {
                            Text("Custom Commands")
                                .font(SettingsDesign.editorialSectionFont)
                                .foregroundStyle(Color.primary)

                            Text("\(customStore.commands.count)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(SettingsDesign.secondaryText)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(SettingsDesign.controlBackground, in: Capsule())
                        }

                        Spacer()

                        Button {
                            isCreatingCommand = true
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "plus")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("Add Command")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundStyle(SettingsDesign.accentBlue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: SettingsDesign.smallControlRadius, style: .continuous)
                                    .fill(SettingsDesign.accentBlue.opacity(0.08))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 4)

                    if customStore.commands.isEmpty {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("No custom commands created yet")
                                    .font(SettingsDesign.bodyFontMedium)
                                    .foregroundStyle(Color.primary)
                                Text("Create custom shortcuts to open apps, URLs, folders, files, or system settings with voice.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(SettingsDesign.secondaryText)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(SettingsDesign.groupBackground, in: RoundedRectangle(cornerRadius: SettingsDesign.groupCornerRadius))
                        .overlay {
                            RoundedRectangle(cornerRadius: SettingsDesign.groupCornerRadius)
                                .strokeBorder(SettingsDesign.separatorColor, lineWidth: 1)
                        }
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(customStore.commands.enumerated()), id: \.element.id) { index, command in
                                if index > 0 {
                                    WFRowDivider(leadingInset: 14)
                                }
                                CustomCommandRow(
                                    command: command,
                                    feedback: testFeedback?.commandId == command.id ? testFeedback : nil,
                                    onToggle: {
                                        customStore.toggle(id: command.id)
                                    },
                                    onEdit: {
                                        editingCommand = command
                                    },
                                    onDelete: {
                                        customStore.delete(id: command.id)
                                    },
                                    onTest: {
                                        let result = CustomCommandExecutor.shared.execute(command)
                                        switch result {
                                        case .success(let feedback):
                                            testFeedback = (command.id, feedback, true)
                                        case .failure(let err):
                                            testFeedback = (command.id, err, false)
                                        }
                                        Task {
                                            try? await Task.sleep(nanoseconds: 3_500_000_000)
                                            if testFeedback?.commandId == command.id {
                                                testFeedback = nil
                                            }
                                        }
                                    }
                                )
                            }
                        }
                        .background(SettingsDesign.groupBackground, in: RoundedRectangle(cornerRadius: SettingsDesign.groupCornerRadius))
                        .overlay {
                            RoundedRectangle(cornerRadius: SettingsDesign.groupCornerRadius)
                                .strokeBorder(SettingsDesign.separatorColor, lineWidth: 1)
                        }
                    }
                }
                .padding(.horizontal, SettingsDesign.contentHorizontalMargin)
                .opacity(isEnabled ? 1.0 : 0.5)

                // Divider between custom and built-in commands
                WFRowDivider(leadingInset: 0)
                    .padding(.horizontal, SettingsDesign.contentHorizontalMargin)
                    .padding(.top, 4)

                // Built-in Commands Section Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Built-in Commands")
                        .font(SettingsDesign.editorialSectionFont)
                        .foregroundStyle(Color.primary)
                        .padding(.leading, 4)

                    // Table Header
                    HStack(spacing: 16) {
                        Text("Command")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.6)
                            .frame(width: 250, alignment: .leading)

                        Text("How It Works")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                }
                .padding(.horizontal, SettingsDesign.contentHorizontalMargin)

                // 16 Command Groups in One Scroll Area
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(group.title)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(SettingsDesign.accentBlue)
                                .textCase(.uppercase)
                                .tracking(0.5)
                                .padding(.leading, 4)

                            VStack(spacing: 0) {
                                ForEach(Array(group.commands.enumerated()), id: \.element.identifier) { index, def in
                                    if index > 0 {
                                        WFRowDivider(leadingInset: 14)
                                    }
                                    CommandReferenceRow(definition: def)
                                }
                            }
                            .background(SettingsDesign.groupBackground, in: RoundedRectangle(cornerRadius: SettingsDesign.groupCornerRadius))
                            .overlay {
                                RoundedRectangle(cornerRadius: SettingsDesign.groupCornerRadius)
                                    .strokeBorder(SettingsDesign.separatorColor, lineWidth: 1)
                            }
                        }
                    }
                }
                .padding(.horizontal, SettingsDesign.contentHorizontalMargin)
                .opacity(isEnabled ? 1.0 : 0.5)

            }
            .padding(.vertical, SettingsDesign.contentVerticalPadding)
        }
        .background(SettingsDesign.contentBackground)
        .sheet(isPresented: $isCreatingCommand) {
            CustomCommandEditorSheet { newCmd in
                customStore.add(newCmd)
            }
        }
        .sheet(item: $editingCommand) { cmd in
            CustomCommandEditorSheet(existing: cmd) { updatedCmd in
                customStore.update(updatedCmd)
            }
        }
    }
}

private struct CommandGroup: Identifiable {
    let id: String
    let title: String
    let commands: [CommandDefinition]
}

private struct CommandReferenceRow: View {
    let definition: CommandDefinition

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // LEFT COLUMN: Command / Syntax (~45%)
            HStack(spacing: 6) {
                Text(syntax(for: definition.identifier))
                    .font(SettingsDesign.commandSyntaxFont)
                    .foregroundStyle(Color.primary)

                if definition.risk == .destructive {
                    Text("destructive")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.red.opacity(0.12), in: Capsule())
                } else if definition.risk == .sensitive {
                    Text("sensitive")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                }

                if definition.confirmation == .mandatory {
                    Text("confirms")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(SettingsDesign.accentBlue)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(SettingsDesign.accentBlue.opacity(0.12), in: Capsule())
                }

                Spacer(minLength: 0)
            }
            .frame(width: 250, alignment: .leading)

            // RIGHT COLUMN: How It Works (~55%)
            Text(description(for: definition.identifier))
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(minHeight: 30)
        .wfHoverElevation(cornerRadius: 6)
        .contentShape(Rectangle())
    }

    private func syntax(for id: CommandIdentifier) -> String {
        switch id {
        case .appOpen: return "open <app>"
        case .appQuit: return "quit <app>"
        case .appHide: return "hide <app>"
        case .appSwitch: return "switch to <app>"
        case .settingsOpen: return "open settings"
        case .historyOpen: return "open history"
        case .clipboardCopyLast: return "copy last dictation"
        case .clipboardClear: return "clear clipboard"
        case .clipboardInspect: return "inspect clipboard"
        case .dictationModeFormal: return "switch to formal mode"
        case .dictationModeStandard: return "switch to standard mode"
        case .speechModelReload: return "reload speech model"
        case .browserOpenURL: return "open <url>"
        case .browserSearch: return "search <query>"
        case .browserOpenDefault: return "open browser"
        case .browserOpenPrivate: return "open private window"
        case .whatsAppOpenChat: return "open whatsapp chat with <contact>"
        case .whatsAppSendMessage: return "send message to <contact> saying <msg>"
        case .calendarOpen: return "open calendar"
        case .calendarListEvents: return "list events [for <day>]"
        case .calendarCreateEvent: return "create event <title> [on <date>]"
        case .calendarDeleteEvent: return "delete event <title>"
        case .remindersOpen: return "open reminders"
        case .remindersList: return "list reminders [due <day>]"
        case .remindersCreate: return "create reminder <title> [due <day>]"
        case .remindersComplete: return "complete reminder <title>"
        case .remindersDelete: return "delete reminder <title>"
        case .notesOpen: return "open notes"
        case .notesCreate: return "create note <title> [body <text>]"
        case .notesFind: return "find note <query>"
        case .notesOpenNote: return "open note <title>"
        case .finderOpenLocation: return "open <folder>"
        case .finderFindFiles: return "find files <query>"
        case .finderCreateFolder: return "create folder <name> [in <path>]"
        case .finderCreateFile: return "create file <name> [in <path>]"
        case .finderReveal: return "reveal <path>"
        case .finderTrash: return "trash <path>"
        case .finderRename: return "rename <path> to <new name>"
        case .finderDuplicate: return "duplicate <path>"
        case .systemVolumeUp: return "volume up"
        case .systemVolumeDown: return "volume down"
        case .systemVolumeSet: return "set volume to <0–100>"
        case .systemVolumeMute: return "mute volume"
        case .systemVolumeUnmute: return "unmute volume"
        case .systemVolumeGet: return "get volume"
        case .systemSleep: return "sleep mac"
        case .systemLock: return "lock screen"
        case .systemLogout: return "log out"
        case .systemRestart: return "restart mac"
        case .systemShutdown: return "shut down mac"
        case .systemBattery: return "battery status"
        case .systemMacOSVersion: return "macos version"
        case .systemTime: return "what time is it"
        case .systemDate: return "what's today's date"
        case .contextOpen: return "open that"
        case .contextMessage: return "message that"
        case .contextCheck: return "check that"
        case .contactsFind: return "find contact <name>"
        case .contactsShow: return "show contact <name>"
        case .mailOpen: return "open mail"
        case .mailCompose: return "compose email [to <recipient>]"
        default: return id.rawValue
        }
    }

    private func description(for id: CommandIdentifier) -> String {
        switch id {
        case .appOpen: return "Launches or activates the named application"
        case .appQuit: return "Terminates the application (confirms before quitting)"
        case .appHide: return "Hides all windows of the application"
        case .appSwitch: return "Brings the specified application to the front"
        case .settingsOpen: return "Opens the DailyOps settings window"
        case .historyOpen: return "Opens your past dictations and commands"
        case .clipboardCopyLast: return "Copies your most recent dictation to the clipboard"
        case .clipboardClear: return "Empties the macOS clipboard (requires confirmation)"
        case .clipboardInspect: return "Displays current clipboard text"
        case .dictationModeFormal: return "Switches dictation to rewrite speech into professional tone"
        case .dictationModeStandard: return "Switches dictation to natural speech with auto-punctuation"
        case .speechModelReload: return "Reloads the active speech recognition model"
        case .browserOpenURL: return "Opens the web address in your default browser"
        case .browserSearch: return "Searches Google or YouTube for the phrase"
        case .browserOpenDefault: return "Brings your default browser to the foreground"
        case .browserOpenPrivate: return "Opens a new private or incognito browsing window"
        case .whatsAppOpenChat: return "Opens the direct chat in WhatsApp"
        case .whatsAppSendMessage: return "Sends a message in WhatsApp (requires confirmation)"
        case .calendarOpen: return "Brings Apple Calendar to the foreground"
        case .calendarListEvents: return "Lists scheduled calendar events for today or given day"
        case .calendarCreateEvent: return "Schedules a new event on your calendar"
        case .calendarDeleteEvent: return "Deletes the matching calendar event (confirms)"
        case .remindersOpen: return "Brings Apple Reminders to the foreground"
        case .remindersList: return "Lists pending items from your Reminders list"
        case .remindersCreate: return "Adds a new task to Apple Reminders"
        case .remindersComplete: return "Marks the matching reminder as completed"
        case .remindersDelete: return "Removes the reminder from your list (confirms)"
        case .notesOpen: return "Brings Apple Notes to the foreground"
        case .notesCreate: return "Creates a new note with optional title and body"
        case .notesFind: return "Searches Apple Notes for matching text"
        case .notesOpenNote: return "Opens the specified note in Apple Notes"
        case .finderOpenLocation: return "Opens Desktop, Downloads, Documents, etc. in Finder"
        case .finderFindFiles: return "Searches the file system for matching files"
        case .finderCreateFolder: return "Creates a new folder at the target directory"
        case .finderCreateFile: return "Creates a new blank file at the specified location"
        case .finderReveal: return "Highlights and selects the specified file in Finder"
        case .finderTrash: return "Moves the file or folder to the Trash (confirms)"
        case .finderRename: return "Renames the file or folder"
        case .finderDuplicate: return "Creates a duplicate copy of the file"
        case .systemVolumeUp: return "Increases output volume by one step"
        case .systemVolumeDown: return "Decreases output volume by one step"
        case .systemVolumeSet: return "Sets system volume to a percentage from 0 to 100"
        case .systemVolumeMute: return "Mutes system audio output"
        case .systemVolumeUnmute: return "Restores audio output volume"
        case .systemVolumeGet: return "Checks current system volume level"
        case .systemSleep: return "Puts your Mac to sleep"
        case .systemLock: return "Locks your Mac screen session"
        case .systemLogout: return "Logs out active user session (confirms)"
        case .systemRestart: return "Restarts your Mac (confirms)"
        case .systemShutdown: return "Shuts down your Mac (confirms)"
        case .systemBattery: return "Reports current battery level and power source"
        case .systemMacOSVersion: return "Reports the installed macOS version"
        case .systemTime: return "Reports the current time"
        case .systemDate: return "Reports today's date"
        case .contextOpen: return "Opens the link or item referenced in recent context"
        case .contextMessage: return "Sends a message using recent recipient context"
        case .contextCheck: return "Inspects or confirms the recent contextual command"
        case .contactsFind: return "Finds contact details in your address book"
        case .contactsShow: return "Opens the person's contact card in Apple Contacts"
        case .mailOpen: return "Brings Apple Mail to the foreground"
        case .mailCompose: return "Drafts a new email with optional recipient and subject"
        default: return "Executes command"
        }
    }
}

// MARK: - Custom Command Row

private struct CustomCommandRow: View {
    let command: CustomCommand
    let feedback: (commandId: UUID, message: String, isSuccess: Bool)?
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onTest: () -> Void

    @State private var isHovered = false
    @State private var isDeleteHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Toggle
            Toggle("", isOn: Binding(
                get: { command.isEnabled },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)

            // Command name & Trigger/Action Information
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(command.triggerPhrase)
                        .font(SettingsDesign.commandSyntaxFont)
                        .foregroundStyle(Color.primary)

                    if !command.customDescription.isEmpty {
                        Text("— \(command.customDescription)")
                            .font(SettingsDesign.captionFont)
                            .foregroundStyle(SettingsDesign.secondaryText)
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: command.actionType.icon)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(SettingsDesign.secondaryText.opacity(0.8))

                    Text(command.target)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(SettingsDesign.secondaryText.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Trailing actions in DictationRow's visual language
            HStack(spacing: 8) {
                // Test button with compact feedback
                Button(action: onTest) {
                    ZStack {
                        if let feedback = feedback {
                            Image(systemName: feedback.isSuccess ? "checkmark" : "exclamationmark.triangle")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(feedback.isSuccess ? Color.green : Color.orange)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.secondary)
                        }
                    }
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Test command")

                // Edit button
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Edit command")

                // Delete button
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(isDeleteHovered ? Color.red : Color.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isDeleteHovered = $0 }
                .help("Delete command")
            }
            .opacity(isHovered || feedback != nil ? 1.0 : 0.45)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(minHeight: 38)
        .wfHoverElevation(cornerRadius: SettingsDesign.smallControlRadius)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

// MARK: - Custom Command Editor Sheet

private struct CustomCommandEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let existingCommand: CustomCommand?
    let onSave: (CustomCommand) -> Void

    @State private var triggerPhrase: String = ""
    @State private var actionType: CustomCommandActionType = .openApplication
    @State private var target: String = ""
    @State private var customDescription: String = ""
    @State private var isEnabled: Bool = true

    init(existing: CustomCommand? = nil, onSave: @escaping (CustomCommand) -> Void) {
        self.existingCommand = existing
        self.onSave = onSave
        _triggerPhrase = State(initialValue: existing?.triggerPhrase ?? "")
        _actionType = State(initialValue: existing?.actionType ?? .openApplication)
        _target = State(initialValue: existing?.target ?? "")
        _customDescription = State(initialValue: existing?.customDescription ?? "")
        _isEnabled = State(initialValue: existing?.isEnabled ?? true)
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text(existingCommand == nil ? "Add Custom Command" : "Edit Custom Command")
                    .font(SettingsDesign.editorialSectionFont)
                    .foregroundStyle(Color.primary)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 14) {
                // Trigger phrase
                VStack(alignment: .leading, spacing: 5) {
                    Text("Trigger Phrase")
                        .font(SettingsDesign.bodyFontMedium)
                    TextField("e.g. open github, edit notes", text: $triggerPhrase)
                        .textFieldStyle(.roundedBorder)
                        .font(SettingsDesign.bodyFont)
                    Text("The spoken phrase that activates this command")
                        .font(.system(size: 11))
                        .foregroundStyle(SettingsDesign.secondaryText)
                }

                // Action Type
                VStack(alignment: .leading, spacing: 5) {
                    Text("Action")
                        .font(SettingsDesign.bodyFontMedium)
                    WFPreferencePicker(
                        selection: $actionType,
                        options: CustomCommandActionType.allCases.map {
                            WFPreferencePickerOption(value: $0, title: $0.displayName, icon: $0.icon)
                        },
                        minWidth: 180
                    )
                }

                // Target
                VStack(alignment: .leading, spacing: 5) {
                    Text("Target")
                        .font(SettingsDesign.bodyFontMedium)
                    TextField(actionType.placeholder, text: $target)
                        .textFieldStyle(.roundedBorder)
                        .font(SettingsDesign.bodyFont)
                    Text(targetHelpText)
                        .font(.system(size: 11))
                        .foregroundStyle(SettingsDesign.secondaryText)
                }

                // Description (Optional)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Description (Optional)")
                        .font(SettingsDesign.bodyFontMedium)
                    TextField("e.g. Opens GitHub in default browser", text: $customDescription)
                        .textFieldStyle(.roundedBorder)
                        .font(SettingsDesign.bodyFont)
                }
            }
            .padding(16)
            .background(SettingsDesign.groupBackground, in: RoundedRectangle(cornerRadius: SettingsDesign.cardRadius))
            .overlay {
                RoundedRectangle(cornerRadius: SettingsDesign.cardRadius)
                    .strokeBorder(SettingsDesign.separatorColor, lineWidth: 1)
            }

            // Buttons
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    let cmd = CustomCommand(
                        id: existingCommand?.id ?? UUID(),
                        triggerPhrase: triggerPhrase.trimmingCharacters(in: .whitespacesAndNewlines),
                        actionType: actionType,
                        target: target.trimmingCharacters(in: .whitespacesAndNewlines),
                        customDescription: customDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                        isEnabled: isEnabled
                    )
                    onSave(cmd)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(triggerPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.borderedProminent)
                .tint(SettingsDesign.accentBlue)
            }
        }
        .padding(24)
        .frame(width: 480)
        .background(SettingsDesign.contentBackground)
    }

    private var targetHelpText: String {
        switch actionType {
        case .openApplication:
            return "Application name (e.g. Safari) or full path to the .app"
        case .openURL:
            return "Web address (e.g. https://apple.com or youtube.com)"
        case .openFolder:
            return "Path to a directory (e.g. ~/Downloads or ~/Documents)"
        case .openFile:
            return "Path to a file (e.g. ~/Documents/Notes.txt)"
        case .systemSettings:
            return "Pane name (default, displays, sound, network, wifi, battery, wallpaper, etc.)"
        }
    }
}