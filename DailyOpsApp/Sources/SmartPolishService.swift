import AppKit
import ApplicationServices
import Carbon.HIToolbox
import os

private let polishLog = Logger(subsystem: AppBrand.bundleIdentifier, category: "smartPolish")

/// Global shortcut coordinator for Option + 1 Smart Polish workflow.
/// Obtains selected text in the active app or falls back to latest dictation,
/// runs it through Apple Writing Tools / smart formatting, and replaces in-place.
@MainActor
final class SmartPolishService {
    static let shared = SmartPolishService()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var isProcessing = false

    /// User configuration toggle for Option + 1 shortcut.
    var isEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: "smartPolishEnabled") as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "smartPolishEnabled")
            if newValue {
                registerShortcut()
            } else {
                unregisterShortcut()
            }
        }
    }

    /// Selected Apple Writing Tools action (proofread, rewrite, formal, concise, summarize).
    var action: AppleWritingToolsAction {
        get {
            guard let raw = UserDefaults.standard.string(forKey: "smartPolishAction"),
                  let action = AppleWritingToolsAction(rawValue: raw) else {
                return .proofread
            }
            return action
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "smartPolishAction")
        }
    }

    /// Whether to replace the original text in-place via synthetic paste.
    var replaceInPlace: Bool {
        get {
            UserDefaults.standard.object(forKey: "smartPolishReplaceInPlace") as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "smartPolishReplaceInPlace")
        }
    }

    func start() {
        guard isEnabled else { return }
        registerShortcut()
    }

    func stop() {
        unregisterShortcut()
    }

    private func registerShortcut() {
        guard hotKeyRef == nil else { return }

        // Install Carbon Event Handler
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, _) -> OSStatus in
                var hotKeyID = EventHotKeyID()
                let err = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                if err == noErr && hotKeyID.signature == 0x53504C53 /* "SPLS" */ {
                    Task { @MainActor in
                        SmartPolishService.shared.handleShortcutTriggered()
                    }
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        guard status == noErr else {
            polishLog.error("Failed to install Carbon event handler: \(status)")
            return
        }

        // Register Option + 1 (kVK_ANSI_1 = 18)
        let hotKeyID = EventHotKeyID(signature: 0x53504C53, id: 1)
        let regStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_1),
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if regStatus == noErr {
            polishLog.info("Option + 1 Smart Polish shortcut successfully registered.")
        } else {
            polishLog.error("RegisterEventHotKey failed: \(regStatus)")
        }
    }

    private func unregisterShortcut() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    /// Workflow execution on Option + 1:
    /// 1. Highlights text or uses last dictation
    /// 2. Runs through Apple Writing Tools / Smart formatting
    /// 3. In-place replacement
    func handleShortcutTriggered() {
        guard !isProcessing else { return }
        let controller = DictationController.shared

        // Only start if not actively recording or dictating
        guard controller.state == .idle || controller.state == .done || controller.state.isError else {
            return
        }

        isProcessing = true
        Task {
            defer { isProcessing = false }
            await executePolishWorkflow(controller: controller)
        }
    }

    private func executePolishWorkflow(controller: DictationController) async {
        let hasAX = HotkeyMonitor.hasAccessibilityPermission()
        if !hasAX {
            controller.setTemporaryError("Accessibility permission required for Smart Polish in active app.")
            _ = HotkeyMonitor.hasAccessibilityPermission(prompt: true)
            return
        }

        let frontmostApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Active App"

        // 1. Try to obtain highlighted text from frontmost application
        var textToPolish = captureSelectedTextViaAccessibility()
        var textWasSelectedInApp = true

        if textToPolish == nil {
            textToPolish = await captureSelectedTextViaCopy()
        }

        // 2. Fall back to latest dictated text if nothing is highlighted
        if textToPolish == nil || textToPolish?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            textWasSelectedInApp = false
            let lastDictation = controller.lastInsertedText
            if !lastDictation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                textToPolish = lastDictation
            }
        }

        // 3. If still empty, inform user via HUD
        guard let sourceText = textToPolish?.trimmingCharacters(in: .whitespacesAndNewlines),
              !sourceText.isEmpty else {
            controller.setTemporaryError("No text selected or dictated to polish.")
            return
        }

        // 4. Update HUD to polishing state
        let actionToRun = self.action
        let statusLabel = textWasSelectedInApp ? "\(actionToRun.label) Selection" : "\(actionToRun.label) Dictation"
        polishLog.info("Polishing text (fromSelection: \(textWasSelectedInApp)) with \(actionToRun.label)")
        controller.setPolishing(action: statusLabel)

        // 5. Send text through Apple Writing Tools / Smart Formatting Pipeline
        let words = controller.vocabulary.words
        var polishedText = sourceText

        if AppleWritingToolsService.isAvailable {
            polishedText = await AppleWritingToolsService.transform(
                sourceText,
                action: actionToRun,
                vocabulary: words
            )
        } else {
            // Local fallback if Apple Intelligence is unavailable
            polishedText = await CleanupService.clean(sourceText, vocabulary: words, formal: actionToRun == .formal)
        }

        // Apply native formatting, spelling check, and typography
        polishedText = TranscriptFormatter.format(polishedText, protectedWords: words)

        // 6. In-place replacement
        if replaceInPlace {
            _ = await PasteService.shared.insert(polishedText)
        }

        // 7. Update last inserted text and record in history
        controller.completePolishing(result: polishedText, original: sourceText, appName: frontmostApp)
    }

    // MARK: - Selected Text Capture

    private func captureSelectedTextViaAccessibility() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElementValue: AnyObject?
        let axResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementValue
        )

        guard axResult == .success, let focusedElement = focusedElementValue else {
            return nil
        }

        let element = focusedElement as! AXUIElement
        var selectedTextValue: AnyObject?
        let textResult = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedTextValue
        )

        if textResult == .success,
           let text = selectedTextValue as? String,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        return nil
    }

    private func captureSelectedTextViaCopy() async -> String? {
        let pasteboard = NSPasteboard.general
        let initialChangeCount = pasteboard.changeCount

        // Synthesize ⌘C
        synthesizeCopy()

        // Wait briefly for frontmost app to service copy event
        try? await Task.sleep(for: .milliseconds(95))

        guard pasteboard.changeCount > initialChangeCount,
              let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return text
    }

    private func synthesizeCopy() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let keyC = CGKeyCode(kVK_ANSI_C)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
