import AppKit
import SwiftUI

/// First-launch window: permissions checklist, model download progress,
/// and a scratch field to try dictation.
@MainActor
enum OnboardingWindow {
    private static var window: NSWindow?

    static func show(controller: DictationController) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingController(rootView: OnboardingView(controller: controller))
        let window = NSWindow(contentViewController: host)
        window.title = "Welcome to DailyOps"
        window.styleMask = [.titled, .closable]
        window.center()
        window.isReleasedWhenClosed = false
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    static func close() {
        window?.close()
        window = nil
    }
}

struct OnboardingView: View {
    let controller: DictationController

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.wesleyBlue.opacity(0.12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.wesleyBlue.opacity(0.3), lineWidth: 1))
                    Image(systemName: "waveform")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Color.wesleyBlue)
                }
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 4) {
                    Text(AppBrand.displayName)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Private dictation for your Mac")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 10) {
                stepRow(
                    done: controller.hasMicPermission,
                    icon: "mic.fill",
                    title: "Microphone",
                    detail: controller.microphone.statusDescription
                ) {
                    Button("Grant") {
                        Task { await controller.microphone.requestIfNeeded() }
                    }
                }

                stepRow(
                    done: controller.hasAccessibilityPermission,
                    icon: "cursorarrow.motionlines",
                    title: "Accessibility",
                    detail: "Needed for the global hotkey and text insertion."
                ) {
                    Button("Open Settings") {
                        NSWorkspace.shared.open(
                            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                        )
                    }
                }

                stepRow(
                    done: true,
                    icon: "keyboard",
                    title: "Keyboard",
                    detail: "Globe/Fn works best when its system action is set to Do Nothing."
                ) {
                    EmptyView()
                }

                stepRow(
                    done: controller.sttState == .ready,
                    icon: "cpu.fill",
                    title: modelTitle,
                    detail: "The speech model is cached locally after the first preparation."
                ) {
                    if controller.sttState == .loading {
                        ProgressView().controlSize(.small)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Test Area")
                    .font(.headline)
                TryItField()
            }

            HStack {
                Text("Hold \(controller.hotkeyLabel) while focused in the test area.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") {
                    UserDefaults.standard.set(true, forKey: "hasOnboarded")
                    OnboardingWindow.close()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(30)
        .frame(width: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(.wesleyBlue)
        .onAppear { controller.refreshPermissions() }
        // Poll each second: permission grants happen in System Settings,
        // outside our process, so there's no notification to observe.
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            controller.refreshPermissions()
        }
    }

    private var modelTitle: String {
        switch controller.sttState {
        case .notLoaded: "Speech model"
        case .loading: "Speech model — downloading / loading…"
        case .ready: "Speech model ready"
        case .failed(let message): "Speech model failed: \(message)"
        }
    }

    @ViewBuilder
    private func stepRow(
        done: Bool,
        icon: String,
        title: String,
        detail: String,
        @ViewBuilder action: () -> some View
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : icon)
                .foregroundStyle(done ? Color.wesleyBlue : Color.secondary)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !done {
                action()
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct TryItField: View {
    @State private var text = ""

    var body: some View {
        TextEditor(text: $text)
            .font(.body)
            .modifier(WritingToolsModifier())
            .scrollContentBackground(.hidden)
            .padding(8)
            .frame(height: 86)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator.opacity(0.7)))
    }
}

private struct WritingToolsModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.writingToolsBehavior(.complete)
        } else {
            content
        }
    }
}
