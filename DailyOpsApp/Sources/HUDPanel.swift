import AppKit
import SwiftUI

/// Floating, non-activating overlay pill at the bottom of the screen.
/// Never takes key focus — the target app must keep receiving keystrokes
/// (and ultimately the synthesized ⌘V) while the HUD is visible.
@MainActor
final class HUDPanelController {
    private let panel: NSPanel
    private let hostingView: NSHostingView<HUDView>
    private var currentHeight: CGFloat = 46

    init(controller: DictationController) {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false

        // Create hosting view with a placeholder, then update with real view that has callback
        hostingView = NSHostingView(rootView: HUDView(controller: controller))
        hostingView.frame = NSRect(x: 0, y: 0, width: 620, height: 78)
        // Explicitly clear: on macOS 26 hosted panel content can pick up an
        // automatic window/glass background, which shows as a grey rounded
        // rectangle behind the pill.
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        if #available(macOS 26.0, *) {
            hostingView.sceneBridgingOptions = []
        }
        panel.contentView = hostingView
        panel.setContentSize(hostingView.frame.size)
        panel.alphaValue = 0

        // Replace root view with one that has the height change callback
        hostingView.rootView = HUDView(controller: controller, onHeightChange: { [weak self] height in
            self?.updateHeight(height)
        })
    }

    private func updateHeight(_ height: CGFloat) {
        let clampedHeight = max(36, min(height, 160))
        guard abs(clampedHeight - currentHeight) > 1 else { return }
        currentHeight = clampedHeight
        let newSize = NSSize(width: 620, height: clampedHeight + 16)
        hostingView.frame.size = newSize
        panel.setContentSize(newSize)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().setFrame(NSRect(origin: panel.frame.origin, size: newSize), display: true)
        }
        position()
    }

    func setInteractive(_ interactive: Bool) {
        panel.ignoresMouseEvents = !interactive
        if interactive {
            panel.makeKey()
        }
    }

    func setVisible(_ visible: Bool) {
        if visible {
            position()
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = visible ? 0.15 : 0.35
            panel.animator().alphaValue = visible ? 1 : 0
        } completionHandler: { [panel] in
            Task { @MainActor in
                if !visible, panel.alphaValue == 0 {
                    panel.orderOut(nil)
                }
            }
        }
    }

    private func position() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.minY + 24
        ))
    }
}
