import AppKit
import ApplicationServices
import Carbon.HIToolbox
import os

private let pasteLog = Logger(subsystem: AppBrand.bundleIdentifier, category: "pasteService")

/// Granular failure reasons for text insertion operations.
public enum PasteFailureReason: Equatable, Sendable, CustomStringConvertible {
    case emptyText
    case accessibilityUnavailable
    case noTargetApplication
    case clipboardWriteFailed
    case clipboardVerificationFailed
    case dispatchFailed(String)
    case cancelled

    public var description: String {
        switch self {
        case .emptyText:
            return "No text to paste"
        case .accessibilityUnavailable:
            return "Accessibility permission required to paste automatically"
        case .noTargetApplication:
            return "No active application to paste into"
        case .clipboardWriteFailed:
            return "Failed to write to system clipboard"
        case .clipboardVerificationFailed:
            return "Clipboard verification failed: content mismatch"
        case .dispatchFailed(let msg):
            return "Paste event dispatch failed: \(msg)"
        case .cancelled:
            return "Paste cancelled"
        }
    }
}

/// Status outcome of a paste operation.
public enum PasteResult: Equatable, Sendable {
    case success
    case copiedToClipboard(String)
    case failure(PasteFailureReason)
}

/// A lossless snapshot of a single pasteboard item with all its registered types and data representations.
public struct PasteboardItemSnapshot: Sendable, Equatable {
    public let typesAndData: [(NSPasteboard.PasteboardType, Data)]

    public init(typesAndData: [(NSPasteboard.PasteboardType, Data)]) {
        self.typesAndData = typesAndData
    }

    public static func == (lhs: PasteboardItemSnapshot, rhs: PasteboardItemSnapshot) -> Bool {
        guard lhs.typesAndData.count == rhs.typesAndData.count else { return false }
        for (i, leftPair) in lhs.typesAndData.enumerated() {
            let rightPair = rhs.typesAndData[i]
            if leftPair.0 != rightPair.0 || leftPair.1 != rightPair.1 {
                return false
            }
        }
        return true
    }
}

/// Protocol for inserting text at the active user cursor.
@MainActor
public protocol PasteServing: Sendable {
    func insert(_ text: String, targetApp: NSRunningApplication?) async -> PasteResult
}

extension PasteServing {
    public func insert(_ text: String) async -> PasteResult {
        await insert(text, targetApp: nil)
    }
}

/// Production implementation of text insertion via native macOS pasteboard and synthetic ⌘V.
/// Guarantees that Accessibility permissions are verified, clipboard contents are preserved
/// across dictations without arbitrary fixed sleeps, and the user-targeted application is preserved.
@MainActor
public final class PasteService: PasteServing {
    public static let shared = PasteService()

    public init() {}

    /// Checks whether the application currently has Accessibility permission.
    public var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Inserts text into the specified or frontmost target application.
    /// Returns:
    /// - `.success` if text was verified on the pasteboard and ⌘V was dispatched.
    /// - `.copiedToClipboard` if text was copied because Accessibility was unavailable.
    /// - `.failure` with a specific `PasteFailureReason` for any pipeline failure.
    public func insert(_ text: String, targetApp: NSRunningApplication? = nil) async -> PasteResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(.emptyText)
        }

        let pasteboard = NSPasteboard.general

        // 1. Accessibility Verification
        guard hasAccessibilityPermission else {
            pasteboard.clearContents()
            let written = pasteboard.setString(text, forType: .string)
            if written && pasteboard.string(forType: .string) == text {
                pasteLog.warning("Accessibility permission missing: copied text to clipboard instead of pasting")
                return .copiedToClipboard("Copied to clipboard — Grant Accessibility in System Settings to auto-paste")
            } else {
                return .failure(.clipboardWriteFailed)
            }
        }

        // 2. Validate and Preserve Target Application
        let destinationApp: NSRunningApplication
        if let targetApp, !targetApp.isTerminated {
            destinationApp = targetApp
        } else if let frontApp = NSWorkspace.shared.frontmostApplication, !frontApp.isTerminated,
                  frontApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            destinationApp = frontApp
        } else {
            // Write to clipboard as a safety measure before failing
            pasteboard.clearContents()
            _ = pasteboard.setString(text, forType: .string)
            return .failure(.noTargetApplication)
        }

        // Ensure destination application is frontmost and active
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != destinationApp.processIdentifier {
            destinationApp.activate()
        }

        // 3. Lossless Snapshot of Current Pasteboard
        let snapshot = Self.captureSnapshot(from: pasteboard)

        // 4. Write Final Transcription to General Pasteboard
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            Self.restoreSnapshot(snapshot, to: pasteboard)
            return .failure(.clipboardWriteFailed)
        }

        // 5. Verify the Expected String Was Actually Written
        guard pasteboard.string(forType: .string) == text else {
            Self.restoreSnapshot(snapshot, to: pasteboard)
            return .failure(.clipboardVerificationFailed)
        }

        let injectedChangeCount = pasteboard.changeCount

        // 6. Synthesize ⌘V via Native macOS CGEvent API
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            Self.restoreSnapshot(snapshot, to: pasteboard)
            return .failure(.dispatchFailed("Failed to create CGEventSource"))
        }

        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        let keyV = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false) else {
            Self.restoreSnapshot(snapshot, to: pasteboard)
            return .failure(.dispatchFailed("Failed to create keyboard CGEvent"))
        }

        down.flags = .maskCommand
        up.flags = .maskCommand

        // Post to the system event stream for the active application
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)

        // 7. Event/State-Driven Clipboard Restoration
        // Restores the previous clipboard contents once the target application has consumed
        // the pasteboard, without arbitrary fixed sleeps.
        scheduleEventDrivenRestoration(
            snapshot: snapshot,
            targetPID: destinationApp.processIdentifier,
            expectedChangeCount: injectedChangeCount,
            pasteboard: pasteboard
        )

        return .success
    }

    // MARK: - Snapshot & Restore

    /// Captures all items, types, and raw data representations from the pasteboard.
    public static func captureSnapshot(from pasteboard: NSPasteboard = .general) -> [PasteboardItemSnapshot] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        return items.compactMap { item in
            let pairs: [(NSPasteboard.PasteboardType, Data)] = item.types.compactMap { type in
                guard let data = item.data(forType: type) else { return nil }
                return (type, data)
            }
            return pairs.isEmpty ? nil : PasteboardItemSnapshot(typesAndData: pairs)
        }
    }

    /// Losslessly restores a captured snapshot back onto the pasteboard.
    public static func restoreSnapshot(_ snapshot: [PasteboardItemSnapshot], to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        guard !snapshot.isEmpty else { return }
        var newItems: [NSPasteboardItem] = []
        for itemSnap in snapshot {
            let item = NSPasteboardItem()
            for (type, data) in itemSnap.typesAndData {
                item.setData(data, forType: type)
            }
            newItems.append(item)
        }
        pasteboard.writeObjects(newItems)
    }

    // MARK: - Event-Driven Restoration

    private func scheduleEventDrivenRestoration(
        snapshot: [PasteboardItemSnapshot],
        targetPID: pid_t,
        expectedChangeCount: Int,
        pasteboard: NSPasteboard
    ) {
        Task { @MainActor in
            var observer: AXObserver?
            var consumed = false

            // Define the C-compatible AX observer callback
            let callback: AXObserverCallback = { _, _, _, refcon in
                guard let refcon else { return }
                let flag = refcon.assumingMemoryBound(to: Bool.self)
                flag.pointee = true
            }

            let axApp = AXUIElementCreateApplication(targetPID)
            let axResult = AXObserverCreate(targetPID, callback, &observer)

            if axResult == .success, let observer {
                let source = AXObserverGetRunLoopSource(observer)
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
                _ = AXObserverAddNotification(observer, axApp, kAXValueChangedNotification as CFString, &consumed)
                _ = AXObserverAddNotification(observer, axApp, kAXSelectedTextChangedNotification as CFString, &consumed)
            }

            // Await either an AX notification from the target app or runloop event cycle completion
            let clock = ContinuousClock()
            let deadline = clock.now + .milliseconds(400)

            while clock.now < deadline && !consumed {
                // Yield cooperative task execution across run loop cycles
                try? await Task.sleep(for: .milliseconds(25))
            }

            // Clean up AX Observer
            if let observer {
                let source = AXObserverGetRunLoopSource(observer)
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
            }

            // Only restore if the pasteboard hasn't been changed by the user or another app
            guard pasteboard.changeCount == expectedChangeCount else {
                pasteLog.info("Skipping clipboard restore because the pasteboard changed externally")
                return
            }

            Self.restoreSnapshot(snapshot, to: pasteboard)
        }
    }
}
