import SwiftUI

struct SmartFormattingPane: View {
    var controller: DictationController?

    // Master & Cleanup Engine
    @AppStorage("smartFormattingEnabled") private var smartFormattingEnabled = true
    @AppStorage("cleanupEnabled") private var cleanupEnabled = true
    @AppStorage("cleanupAlways") private var cleanupAlways = false
    @AppStorage("cleanupMode") private var cleanupMode = "smart"
    @Namespace private var cleanupNamespace

    // Speech Cleanup
    @AppStorage("formatTrimFillers") private var formatTrimFillers = true
    @AppStorage("speechCleanupEnabled") private var speechCleanupEnabled = true
    @AppStorage("formatSelfCorrection") private var formatSelfCorrection = true
    @AppStorage("formatPreserveMeaning") private var formatPreserveMeaning = true

    // Spelling & Typography
    @AppStorage("formatSpellCheck") private var formatSpellCheck = true
    @AppStorage("formatSmartTypography") private var formatSmartTypography = true

    // Spoken Formatting
    @AppStorage("formatSpokenPunctuation") private var formatSpokenPunctuation = true
    @AppStorage("formatTightenSpacing") private var formatTightenSpacing = true
    @AppStorage("formatCapitalization") private var formatCapitalization = ""
    @AppStorage("formatAutoPeriod") private var formatAutoPeriod = true

    // Smart Polish
    @AppStorage("smartPolishEnabled") private var smartPolishEnabled = true
    @AppStorage("smartPolishAction") private var smartPolishAction = AppleWritingToolsAction.proofread.rawValue
    @AppStorage("smartPolishReplaceInPlace") private var smartPolishReplaceInPlace = true

    @AppStorage("promptAwareDictationEnabled") private var promptAwareDictationEnabled = true
    @AppStorage("repeatedSpeechHandling") private var repeatedSpeechHandling = RepeatedSpeechHandling.conservative.rawValue
    @Namespace private var repetitionNamespace

    @State private var appleWritingToolsStatus: AppleWritingToolsStatus = .requiresMacOSUpdate

    init(controller: DictationController? = nil) {
        self.controller = controller
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsDesign.sectionSpacing) {

                // MARK: - Automatic Formatting
                WFSection(title: "Automatic Formatting") {
                    WFToggleRow(
                        "Enable Automatic Formatting",
                        description: "Master switch enabling text normalization, punctuation, and cleanup rules",
                        isOn: $smartFormattingEnabled
                    )

                    WFRowDivider()

                    WFToggleRow(
                        "Prompt-Aware Voice Input",
                        description: "Adapts formatting for developer IDEs, terminals, and AI assistants (Cursor, VS Code, ChatGPT, Claude)",
                        isOn: $promptAwareDictationEnabled
                    )

                    WFRowDivider()

                    WFToggleRow(
                        "Local Text Cleanup",
                        description: "Applies on-device speech cleanup and formatting rules",
                        isOn: $cleanupEnabled
                    )

                    if cleanupEnabled {
                        WFRowDivider()

                        WFRow("Cleanup Mode", description: "Control when polishing is applied") {
                            WFGlassSegmentedControl(
                                selection: Binding(
                                    get: { cleanupAlways ? "always" : (cleanupMode.isEmpty ? "smart" : cleanupMode) },
                                    set: { newMode in
                                        cleanupMode = newMode
                                        cleanupAlways = (newMode == "always")
                                    }
                                ),
                                options: [
                                    WFGlassSegmentOption(value: "smart", title: "Smart"),
                                    WFGlassSegmentOption(value: "whenNeeded", title: "When Needed"),
                                    WFGlassSegmentOption(value: "always", title: "Always")
                                ],
                                height: 28,
                                namespace: cleanupNamespace
                            )
                        }
                    }


                }
                .padding(.horizontal, SettingsDesign.contentHorizontalMargin)

                // MARK: - Speech Cleanup
                WFSection(title: "Speech Cleanup") {
                    WFToggleRow(
                        "Remove Filler Words",
                        description: "Strips verbal hesitations such as \"um\", \"uh\", \"like\", and \"you know\"",
                        isOn: $formatTrimFillers
                    )

                    WFRowDivider()

                    WFToggleRow(
                        "Collapse Repeated Words",
                        description: "Removes accidental repetitions and stutters in spoken input",
                        isOn: $speechCleanupEnabled
                    )

                    WFRowDivider()

                    WFToggleRow(
                        "Handle Self-Corrections",
                        description: "Applies spoken corrections like 'send to John — no, send to Sarah'",
                        isOn: $formatSelfCorrection
                    )

                    WFRowDivider()

                    WFToggleRow(
                        "Preserve Meaningful Speech",
                        description: "Ensures technical terms, numbers, and intended phrasing are never omitted",
                        isOn: $formatPreserveMeaning
                    )

                    WFRowDivider()

                    WFRow("Repeated Speech Handling", description: "Detects and deduplicates accidental immediate repeated sentences") {
                        WFGlassSegmentedControl(
                            selection: $repeatedSpeechHandling,
                            options: RepeatedSpeechHandling.allCases.map {
                                WFGlassSegmentOption(value: $0.rawValue, title: $0.label)
                            },
                            height: 28,
                            namespace: repetitionNamespace
                        )
                    }
                }
                .padding(.horizontal, SettingsDesign.contentHorizontalMargin)

                // MARK: - Spelling & Cleanup
                WFSection(title: "Spelling & Cleanup") {
                    WFToggleRow(
                        "Native Spell Checking",
                        description: "Uses Apple NSSpellChecker to fix misspelled words while protecting custom vocabulary",
                        isOn: $formatSpellCheck
                    )
                }
                .padding(.horizontal, SettingsDesign.contentHorizontalMargin)

                // MARK: - Smart Typography
                WFSection(title: "Smart Typography") {
                    WFToggleRow(
                        "Smart Quotes & Symbols",
                        description: "Replaces straight quotes with curly quotes, double hyphens with em-dashes, and three dots with ellipses",
                        isOn: $formatSmartTypography
                    )
                }
                .padding(.horizontal, SettingsDesign.contentHorizontalMargin)

                // MARK: - Spoken Formatting
                WFSection(title: "Spoken Formatting") {
                    WFToggleRow(
                        "Spoken Punctuation Commands",
                        description: "Interprets words like \"comma\", \"period\", \"exclamation point\", and \"new line\"",
                        isOn: $formatSpokenPunctuation
                    )

                    WFRowDivider()

                    WFToggleRow(
                        "Tighten Spacing",
                        description: "Removes unnecessary spaces immediately preceding punctuation",
                        isOn: $formatTightenSpacing
                    )

                    WFRowDivider()

                    WFRow("Capitalization Style", description: "Default capitalization applied to dictated sentences") {
                        WFPreferencePicker(
                            selection: $formatCapitalization,
                            options: [
                                WFPreferencePickerOption(value: "sentence", title: "Sentence case"),
                                WFPreferencePickerOption(value: "title", title: "Title Case"),
                                WFPreferencePickerOption(value: "preserve", title: "Preserve as spoken")
                            ],
                            minWidth: 160
                        )
                    }

                    WFRowDivider()

                    WFToggleRow(
                        "Auto-Add Terminal Period",
                        description: "Appends a period at the end of completed utterances if none was spoken",
                        isOn: $formatAutoPeriod
                    )
                }
                .padding(.horizontal, SettingsDesign.contentHorizontalMargin)

                // MARK: - Smart Polish (Option + 1)
                WFSection(title: "Smart Polish (Option + 1)") {
                    WFToggleRow(
                        "Global Polish Shortcut",
                        description: "Press Option + 1 anywhere in macOS to polish selected text",
                        isOn: $smartPolishEnabled
                    )
                    .onChange(of: smartPolishEnabled) { _, newValue in
                        if newValue {
                            SmartPolishService.shared.start()
                        } else {
                            SmartPolishService.shared.stop()
                        }
                    }

                    if smartPolishEnabled {
                        WFRowDivider()

                        WFRow("Polish Action", description: "Transformation applied when pressing the shortcut") {
                            WFPreferencePicker(
                                selection: $smartPolishAction,
                                options: AppleWritingToolsAction.allCases.map {
                                    WFPreferencePickerOption(value: $0.rawValue, title: $0.label)
                                },
                                minWidth: 160
                            )
                        }

                        WFRowDivider()

                        WFToggleRow(
                            "Replace in Place",
                            description: "Directly overwrites the highlighted text rather than copying to clipboard",
                            isOn: $smartPolishReplaceInPlace
                        )
                    }
                }
                .padding(.horizontal, SettingsDesign.contentHorizontalMargin)

                // MARK: - Tone / Style
                if let controller {
                    WFSection(title: "Tone & Style") {
                        WFRow("Default Dictation Tone", description: "Select natural dictation or polished professional tone") {
                            WFPreferencePicker(
                                selection: Binding(
                                    get: { controller.writingMode },
                                    set: { controller.writingMode = $0 }
                                ),
                                options: WritingMode.allCases.map {
                                    WFPreferencePickerOption(value: $0, title: $0.label)
                                },
                                minWidth: 160
                            )
                        }
                    }
                    .padding(.horizontal, SettingsDesign.contentHorizontalMargin)
                }

                // MARK: - Apple Writing Tools
                WFSection(title: "Apple Writing Tools") {
                    WFRow("Hardware Capability", description: appleWritingToolsStatus.detailMessage) {
                        Text(appleWritingToolsStatus.label)
                            .font(SettingsDesign.smallLabelFontMedium)
                            .foregroundStyle(SettingsDesign.accentBlue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(SettingsDesign.accentBlue.opacity(0.10), in: Capsule())
                    }
                }
                .padding(.horizontal, SettingsDesign.contentHorizontalMargin)

            }
            .padding(.vertical, SettingsDesign.contentVerticalPadding)
        }
        .background(SettingsDesign.contentBackground)
        .task {
            appleWritingToolsStatus = AppleWritingToolsStatus.current
        }
    }
}