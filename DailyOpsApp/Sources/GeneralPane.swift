import ServiceManagement
import SwiftUI

struct GeneralPane: View {
    @Bindable var controller: DictationController

    // Speech Engine settings (moved here from Dictation)
    @AppStorage("sttEngine") private var sttEngine = SpeechEngine.parakeet.rawValue
    @AppStorage("sttModelVersion") private var modelVersion = "v3"
    @AppStorage("whisperModel") private var whisperModel = WhisperVariant.baseEn.rawValue
    @AppStorage("whisperLanguage") private var whisperLanguage = "auto"

    // Startup & UI options
    @AppStorage("appearance") private var appearance = AppAppearance.system.rawValue
    @AppStorage("customHotkeyChoice") private var customChoiceRaw = HotkeyChoice.rightCommand.rawValue
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var showAdvancedOptions = false
    @State private var showingOnboardReset = false
    @State private var resetSuccess = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsDesign.sectionSpacing) {

                // MARK: - Speech Engine
                WFSection(title: "Speech Engine") {
                    WFRow("Engine", description: "Select the on-device transcription engine") {
                        WFPreferencePicker(
                            selection: $sttEngine,
                            options: SpeechEngine.allCases.map {
                                WFPreferencePickerOption(value: $0.rawValue, title: $0.label)
                            },
                            minWidth: 160
                        ) { _ in
                            controller.reloadModel()
                        }
                    }

                    WFRowDivider()

                    if sttEngine == SpeechEngine.parakeet.rawValue {
                        WFRow("Model", description: "Parakeet CoreML model") {
                            WFPreferencePicker(
                                selection: $modelVersion,
                                options: [
                                    WFPreferencePickerOption(value: "v3", title: "Parakeet v3 — 25 languages"),
                                    WFPreferencePickerOption(value: "v2", title: "Parakeet v2 — English only")
                                ],
                                minWidth: 200
                            ) { _ in
                                controller.reloadModel()
                            }
                        }
                    } else {
                        WFRow("Model", description: "Whisper model variant") {
                            WFPreferencePicker(
                                selection: $whisperModel,
                                options: WhisperVariant.allCases.map {
                                    WFPreferencePickerOption(value: $0.rawValue, title: $0.label)
                                },
                                minWidth: 200
                            ) { _ in
                                controller.reloadModel()
                            }
                        }

                        WFRowDivider()

                        WFRow("Language", description: "Recognition language") {
                            WFPreferencePicker(
                                selection: $whisperLanguage,
                                options: [
                                    WFPreferencePickerOption(value: "auto", title: "Auto-detect (recommended)"),
                                    WFPreferencePickerOption(value: "en", title: "English"),
                                    WFPreferencePickerOption(value: "hi", title: "Hindi"),
                                    WFPreferencePickerOption(value: "es", title: "Spanish"),
                                    WFPreferencePickerOption(value: "fr", title: "French"),
                                    WFPreferencePickerOption(value: "de", title: "German"),
                                    WFPreferencePickerOption(value: "ja", title: "Japanese"),
                                    WFPreferencePickerOption(value: "zh", title: "Chinese")
                                ],
                                minWidth: 200
                            )
                        }
                    }

                    WFRowDivider()

                    WFRow("Status", description: "Current state of speech engine") {
                        HStack(spacing: 8) {
                            switch controller.sttState {
                            case .ready:
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 7, height: 7)
                                    Text("Ready")
                                        .font(SettingsDesign.bodyFont)
                                        .foregroundStyle(.secondary)
                                }
                            case .loading:
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("Loading…")
                                        .font(SettingsDesign.bodyFont)
                                        .foregroundStyle(.secondary)
                                }
                            case .notLoaded:
                                Text("Not loaded")
                                    .font(SettingsDesign.bodyFont)
                                    .foregroundStyle(.secondary)
                            case .failed(let message):
                                Text(message)
                                    .font(SettingsDesign.bodyFont)
                                    .foregroundStyle(.red)
                            }

                            Button {
                                controller.reloadModel()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.borderless)
                            .help("Reload model")
                        }
                    }
                }
                .padding(.horizontal, SettingsDesign.contentHorizontalMargin)

                // MARK: - Appearance Theme Selector (Capsule Segmented Control)
                WFSection(title: "Appearance") {
                    WFRow("Theme", description: "Select Light, Dark, or automatically match macOS") {
                        ThemeCapsuleSelector(appearance: $appearance)
                    }
                }
                .padding(.horizontal, SettingsDesign.contentHorizontalMargin)

                // MARK: - Shortcut Selection (Polished Selectable Cards)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Push-to-Talk Shortcut")
                        .sectionHeaderStyle()
                        .padding(.leading, 4)

                    let customChoice = HotkeyChoice(rawValue: customChoiceRaw) ?? .rightCommand

                    HStack(spacing: 9) {
                        ShortcutOptionCard(
                            title: "Fn / Globe",
                            subtitle: "Hold 🌐",
                            icon: "globe",
                            isSelected: controller.hotkeyChoice == .fn,
                            action: { controller.hotkeyChoice = .fn }
                        )

                        ShortcutOptionCard(
                            title: "Right Option",
                            subtitle: "Hold ⌥",
                            icon: "option",
                            isSelected: controller.hotkeyChoice == .rightOption,
                            action: { controller.hotkeyChoice = .rightOption }
                        )

                        ShortcutOptionCard(
                            title: customChoice.label,
                            subtitle: "Hold \(customChoice.shortKeyName)",
                            icon: customChoice.icon,
                            isSelected: controller.hotkeyChoice == customChoice,
                            menuChoices: HotkeyChoice.customChoices,
                            onSelectChoice: { choice in
                                customChoiceRaw = choice.rawValue
                                controller.hotkeyChoice = choice
                            },
                            action: { controller.hotkeyChoice = customChoice }
                        )
                    }

                    if controller.hotkeyChoice == .fn {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(SettingsDesign.accentBlue)
                            Text("To prevent macOS emoji picker from opening, set System Settings → Keyboard → \"Press 🌐 key to\" → Do Nothing.")
                                .font(SettingsDesign.captionFont)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 4)
                        .padding(.leading, 4)
                    } else {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(SettingsDesign.accentBlue)
                            Text("Holding the \(controller.hotkeyChoice.label) (\(controller.hotkeyChoice.shortKeyName)) key will trigger push-to-talk dictation.")
                                .font(SettingsDesign.captionFont)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 4)
                        .padding(.leading, 4)
                    }
                }
                .padding(.horizontal, SettingsDesign.contentHorizontalMargin)

                // MARK: - Startup & Preferences
                WFSection {
                    WFToggleRow(
                        "Launch at Login",
                        description: "Start DailyOps automatically when you log into your Mac",
                        isOn: $launchAtLogin
                    )
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }

                    WFRowDivider()

                    WFToggleRow(
                        "Show Advanced Options",
                        description: "Reveal version details, bundle ID, and onboarding reset",
                        isOn: $showAdvancedOptions
                    )
                }
                .padding(.horizontal, SettingsDesign.contentHorizontalMargin)

                // MARK: - Advanced Options (Revealed when enabled)
                if showAdvancedOptions {
                    WFSection(title: "Advanced Options") {
                        WFInfoRow(
                            "Version",
                            value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
                        )

                        WFRowDivider()

                        WFInfoRow(
                            "Build",
                            value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
                        )

                        WFRowDivider()

                        WFInfoRow(
                            "Bundle ID",
                            value: AppBrand.bundleIdentifier,
                            selectable: true
                        )

                        WFRowDivider()

                        WFButtonRow(
                            "Reset Onboarding",
                            description: "Rerun initial setup and microphone permissions on next launch",
                            buttonLabel: "Reset Onboarding…",
                            systemImage: "arrow.counterclockwise"
                        ) {
                            showingOnboardReset = true
                        }
                        .confirmationDialog(
                            "Reset Onboarding?",
                            isPresented: $showingOnboardReset,
                            titleVisibility: .visible
                        ) {
                            Button("Reset Onboarding", role: .destructive) {
                                UserDefaults.standard.removeObject(forKey: "hasOnboarded")
                                resetSuccess = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    resetSuccess = false
                                }
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("The welcome guide will appear the next time DailyOps launches.")
                        }

                        if resetSuccess {
                            WFRowDivider()
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.green)
                                Text("Onboarding state reset.")
                                    .font(SettingsDesign.captionFont)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, SettingsDesign.rowHorizontalPadding)
                            .padding(.vertical, 8)
                        }
                    }
                    .padding(.horizontal, SettingsDesign.contentHorizontalMargin)
                }

            }
            .padding(.vertical, SettingsDesign.contentVerticalPadding)
        }
        .background(SettingsDesign.contentBackground)
    }
}

// MARK: - Theme Capsule Segmented Selector

private struct ThemeCapsuleSelector: View {
    @Binding var appearance: String
    @Namespace private var themeNamespace

    private let options = [
        WFGlassSegmentOption(value: AppAppearance.light.rawValue, title: "Light", icon: "sun.max.fill"),
        WFGlassSegmentOption(value: AppAppearance.dark.rawValue, title: "Dark", icon: "moon.fill"),
        WFGlassSegmentOption(value: AppAppearance.system.rawValue, title: "System", icon: "circle.circle")
    ]

    var body: some View {
        WFGlassSegmentedControl(
            selection: $appearance,
            options: options,
            height: 30,
            namespace: themeNamespace
        )
    }
}

// MARK: - Selectable Shortcut Option Card

private struct ShortcutOptionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let isSelected: Bool
    var menuChoices: [HotkeyChoice]? = nil
    var onSelectChoice: ((HotkeyChoice) -> Void)? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                // Top-right restrained checkmark
                if isSelected {
                    ZStack {
                        Circle()
                            .fill(SettingsDesign.accentBlue.opacity(0.12))
                            .frame(width: 18, height: 18)
                        Image(systemName: "checkmark")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(SettingsDesign.accentBlue)
                    }
                    .padding(7)
                }

                // Centered Card Content
                VStack(spacing: 5) {
                    Spacer(minLength: 0)

                    Image(systemName: icon)
                        .font(.system(size: 21, weight: .regular))
                        .foregroundStyle(isSelected ? SettingsDesign.accentBlue : SettingsDesign.secondaryText)
                        .frame(height: 24)

                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            Text(title)
                                .font(SettingsDesign.bodyFontMedium)
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)

                            if menuChoices != nil {
                                Menu {
                                    if let menuChoices, let onSelectChoice {
                                        ForEach(menuChoices) { choice in
                                            Button {
                                                onSelectChoice(choice)
                                            } label: {
                                                HStack {
                                                    Image(systemName: choice.icon)
                                                    Text(choice.label)
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 8, weight: .semibold))
                                        .foregroundStyle(SettingsDesign.secondaryText.opacity(0.8))
                                }
                                .menuStyle(.borderlessButton)
                                .menuIndicator(.hidden)
                                .fixedSize()
                            }
                        }

                        Text(subtitle)
                            .font(SettingsDesign.captionFont)
                            .foregroundStyle(SettingsDesign.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background {
                RoundedRectangle(cornerRadius: SettingsDesign.shortcutCardRadius, style: .continuous)
                    .fill(isHovered ? SettingsDesign.hoverBackground : SettingsDesign.controlBackground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: SettingsDesign.shortcutCardRadius, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? SettingsDesign.accentBlue
                            : (isHovered ? SettingsDesign.separatorColor.opacity(0.85) : SettingsDesign.separatorColor),
                        lineWidth: isSelected ? 1.75 : 0.75
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: SettingsDesign.shortcutCardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}