import AppKit

/// Boundary for opening WhatsApp deep links or native URLs.
@MainActor
protocol WhatsAppControlling: Sendable {
    func open(_ url: URL) throws
}

/// Live implementation that calls NSWorkspace.open(url).
@MainActor
final class SystemWhatsAppControl: WhatsAppControlling {
    func open(_ url: URL) throws {
        let success = NSWorkspace.shared.open(url)
        if !success {
            throw CommandExecutionError.operationFailed("Failed to open WhatsApp URL.")
        }
    }
}
