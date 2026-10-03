import AppKit
import Foundation

/// Summary of clipboard content.
struct ClipboardContent: Equatable, Sendable {
    let hasText: Bool
    let text: String?
    let typeDescription: String
}

/// Abstract interface for Clipboard operations.
@MainActor
protocol ClipboardControlling: Sendable {
    func inspectClipboard() throws -> ClipboardContent
}

/// Concrete Clipboard controller using NSPasteboard.
@MainActor
final class SystemClipboardControl: ClipboardControlling {
    private let pasteboard = NSPasteboard.general

    func inspectClipboard() throws -> ClipboardContent {
        // Check for plain text first
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            return ClipboardContent(
                hasText: true,
                text: text,
                typeDescription: "text"
            )
        }

        // Check for other common types
        if pasteboard.canReadObject(forClasses: [NSURL.self], options: nil) {
            if let url = pasteboard.readObjects(forClasses: [NSURL.self], options: nil)?.first as? URL {
                return ClipboardContent(
                    hasText: true,
                    text: url.absoluteString,
                    typeDescription: "URL"
                )
            }
        }

        if pasteboard.canReadObject(forClasses: [NSColor.self], options: nil) {
            if let color = pasteboard.readObjects(forClasses: [NSColor.self], options: nil)?.first as? NSColor {
                return ClipboardContent(
                    hasText: true,
                    text: color.hexString,
                    typeDescription: "color"
                )
            }
        }

        // Check if there's any content at all
        if pasteboard.changeCount > 0 {
            let types = pasteboard.types ?? []
            let typeNames = types.map { $0.rawValue }.joined(separator: ", ")
            return ClipboardContent(
                hasText: false,
                text: nil,
                typeDescription: "non-text content (\(typeNames))"
            )
        }

        return ClipboardContent(
            hasText: false,
            text: nil,
            typeDescription: "empty"
        )
    }
}

/// Fake Clipboard controller for unit testing.
@MainActor
final class FakeClipboardControl: ClipboardControlling {
    var contentToReturn: ClipboardContent?
    var shouldFail: Bool = false

    func inspectClipboard() throws -> ClipboardContent {
        if shouldFail {
            throw CommandExecutionError.operationFailed("Clipboard inspection failed.")
        }
        return contentToReturn ?? ClipboardContent(hasText: false, text: nil, typeDescription: "empty")
    }
}

/// Executes clipboard inspection commands.
@MainActor
struct ClipboardCommandExecutor: CommandExecuting {
    private let control: ClipboardControlling

    let supportedIdentifiers: Set<CommandIdentifier> = [
        .clipboardInspect
    ]

    init(control: ClipboardControlling) {
        self.control = control
    }

    func execute(_ intent: CommandIntent, context: CommandContext) throws -> String {
        guard case .clipboardInspect = intent.arguments else {
            throw CommandExecutionError.unsupported(intent.identifier)
        }

        let content = try control.inspectClipboard()

        if content.typeDescription == "empty" {
            return "Clipboard is empty."
        }

        if content.hasText, let text = content.text {
            let preview = text.count > 100 ? String(text.prefix(100)) + "..." : text
            return "Clipboard (\(content.typeDescription)): \"\(preview)\""
        } else {
            return "Clipboard contains \(content.typeDescription)."
        }
    }
}

// MARK: - NSColor Extension for Hex String
extension NSColor {
    var hexString: String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        // Convert to sRGB color space if needed
        let colorSpace = NSColorSpace.sRGB
        guard let rgbColor = self.usingColorSpace(colorSpace) else {
            return "unknown"
        }
        rgbColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        let r = Int(round(red * 255))
        let g = Int(round(green * 255))
        let b = Int(round(blue * 255))
        let a = Int(round(alpha * 255))

        if a == 255 {
            return String(format: "#%02X%02X%02X", r, g, b)
        } else {
            return String(format: "#%02X%02X%02X%02X", r, g, b, a)
        }
    }
}