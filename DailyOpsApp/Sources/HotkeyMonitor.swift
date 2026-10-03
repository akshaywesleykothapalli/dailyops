import AppKit
import CoreGraphics

enum HotkeyChoice: String, CaseIterable, Identifiable, Sendable {
    case fn
    case rightOption
    case rightCommand
    case leftCommand
    case leftOption
    case control
    case shift

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fn: "Fn / Globe"
        case .rightOption: "Right Option"
        case .rightCommand: "Right Command"
        case .leftCommand: "Left Command"
        case .leftOption: "Left Option"
        case .control: "Control"
        case .shift: "Shift"
        }
    }

    var shortKeyName: String {
        switch self {
        case .fn: "🌐"
        case .rightOption, .leftOption: "⌥"
        case .rightCommand, .leftCommand: "⌘"
        case .control: "⌃"
        case .shift: "⇧"
        }
    }

    var icon: String {
        switch self {
        case .fn: "globe"
        case .rightOption, .leftOption: "option"
        case .rightCommand, .leftCommand: "command"
        case .control: "control"
        case .shift: "shift"
        }
    }

    var keyCode: Int64 {
        switch self {
        case .fn: 63
        case .rightOption: 61
        case .leftOption: 58
        case .rightCommand: 54
        case .leftCommand: 55
        case .control: 59
        case .shift: 56
        }
    }

    var flag: CGEventFlags {
        switch self {
        case .fn: .maskSecondaryFn
        case .rightOption, .leftOption: .maskAlternate
        case .rightCommand, .leftCommand: .maskCommand
        case .control: .maskControl
        case .shift: .maskShift
        }
    }

    func isPressed(in flags: CGEventFlags) -> Bool {
        flags.contains(flag)
    }

    func isPressed(in flags: NSEvent.ModifierFlags) -> Bool {
        switch self {
        case .fn:
            return flags.contains(.function)
        case .rightOption, .leftOption:
            return flags.contains(.option)
        case .rightCommand, .leftCommand:
            return flags.contains(.command)
        case .control:
            return flags.contains(.control)
        case .shift:
            return flags.contains(.shift)
        }
    }

    static var customChoices: [HotkeyChoice] {
        [.rightCommand, .leftCommand, .leftOption, .control, .shift]
    }
}

/// Listens system-wide for the push-to-talk modifier key via a CGEventTap,
/// supplemented with AppKit global and local event monitors for maximum resilience
/// against event tap timeouts and sleep/wake cycles.
@MainActor
final class HotkeyMonitor {
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    var hotkey: HotkeyChoice = .fn {
        didSet {
            isHeld = false
        }
    }

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var wakeObserver: NSObjectProtocol?
    private var activeObserver: NSObjectProtocol?
    private(set) var isHeld = false

    static func hasAccessibilityPermission(prompt: Bool = false) -> Bool {
        // kAXTrustedCheckOptionPrompt is a mutable C global, which Swift 6
        // concurrency checking rejects; its value is this stable literal.
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func start() -> Bool {
        setupMonitors()

        guard tap == nil else { return true }

        let mask: CGEventMask = 1 << CGEventType.flagsChanged.rawValue
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                if let userInfo {
                    let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                    MainActor.assumeIsolated {
                        monitor.handle(type: type, event: event)
                    }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        ) else {
            log.warning("Event tap creation FAILED (AX trusted: \(Self.hasAccessibilityPermission()))")
            return false
        }
        log.info("Event tap installed (AX trusted: \(Self.hasAccessibilityPermission()))")

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func setupMonitors() {
        if globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                MainActor.assumeIsolated {
                    self?.handleNSEvent(event)
                }
            }
        }
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                MainActor.assumeIsolated {
                    self?.handleNSEvent(event)
                }
                return event
            }
        }
        if wakeObserver == nil {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handleSystemWake()
                }
            }
        }
        if activeObserver == nil {
            activeObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.verifyTapHealth()
                }
            }
        }
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        if let activeObserver {
            NotificationCenter.default.removeObserver(activeObserver)
            self.activeObserver = nil
        }
        tap = nil
        runLoopSource = nil
        isHeld = false
    }

    private func updateState(pressed: Bool) {
        guard pressed != isHeld else { return }
        isHeld = pressed
        if pressed {
            log.info("Hotkey DOWN (\(self.hotkey.label))")
            onKeyDown?()
        } else {
            log.info("Hotkey UP (\(self.hotkey.label))")
            onKeyUp?()
        }
    }

    private func handle(type: CGEventType, event: CGEvent) {
        // The system disables taps that stall or when the machine sleeps.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            log.warning("Event tap disabled by system (\(type.rawValue)), re-enabling tap immediately")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            // Recover state if key is currently pressed so the first press after idle is not dropped
            let currentFlags = CGEventSource.flagsState(.combinedSessionState)
            let pressed = hotkey.isPressed(in: currentFlags)
            updateState(pressed: pressed)
            return
        }
        guard type == .flagsChanged else { return }
        guard event.getIntegerValueField(.keyboardEventKeycode) == hotkey.keyCode else { return }

        let pressed = hotkey.isPressed(in: event.flags)
        updateState(pressed: pressed)
    }

    private func handleNSEvent(_ event: NSEvent) {
        guard event.keyCode == UInt16(hotkey.keyCode) else { return }
        let pressed = hotkey.isPressed(in: event.modifierFlags)
        updateState(pressed: pressed)
    }

    private func handleSystemWake() {
        log.info("System wake notification received — re-arming hotkey tap if needed")
        verifyTapHealth()
        let currentFlags = CGEventSource.flagsState(.combinedSessionState)
        let pressed = hotkey.isPressed(in: currentFlags)
        updateState(pressed: pressed)
    }

    func verifyTapHealth() {
        if let tap {
            if !CGEvent.tapIsEnabled(tap: tap) {
                log.warning("Event tap was disabled; re-enabling now")
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        } else if Self.hasAccessibilityPermission() {
            log.info("Re-installing event tap after invalidation")
            _ = start()
        }
    }
}
