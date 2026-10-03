import SwiftUI

/// Composition point for the unit-test host. The test bundle runs inside the
/// real app process, so production startup must be skipped there; every other
/// launch path (normal, Finder reopen, --selftest) keeps full startup.
enum AppStartup {
    static var isTestHost: Bool {
        NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

/// Starting the pipeline in App.init is too early: AppKit ignores window
/// ordering before the app finishes launching, so the HUD's first
/// appearance silently no-ops. Everything with UI side effects waits for
/// applicationDidFinishLaunching.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            // The XCTest host launches the real app bundle; without this guard
            // every test run would register the global hotkey, warm speech
            // models and open windows. Production startup is unchanged.
            guard !AppStartup.isTestHost else { return }
            // Refresh the running Dock tile from this bundle rather than a stale
            // Launch Services icon cached under the unchanged app identity.
            if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
               let icon = NSImage(contentsOf: iconURL) {
                NSApp.applicationIconImage = icon
            }
            if !SelfTest.runIfRequested() {
                DictationController.shared.start()
                if UserDefaults.standard.bool(forKey: "hasOnboarded") {
                    MainWindow.show(controller: DictationController.shared)
                }
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        MainActor.assumeIsolated {
            guard !AppStartup.isTestHost else { return }
            DictationController.shared.refreshPermissions()
        }
    }

    /// Double-clicking the app in Finder while it runs lands here: show a
    /// window so there's always a way to see that DailyOps is alive, even
    /// if the menu bar icon is hidden (e.g. under the notch).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated {
            MainWindow.show(controller: DictationController.shared)
        }
        return true
    }
}

@main
struct DailyOpsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("appearance") private var appearance = AppAppearance.system.rawValue

    private var controller: DictationController { .shared }

    var body: some Scene {
        MenuBarExtra(AppBrand.displayName, systemImage: controller.state.menuBarSymbol) {
            StatusMenuHeader(controller: controller)

            if !controller.isReady {
                Button("Grant access in System Settings…") {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                    )
                }
            }

            Button("Reload Speech Model") {
                controller.reloadModel()
            }
            .disabled(controller.state == .recording || controller.state == .transcribing || controller.state == .cleaning)

            Button("Copy Last Dictation") {
                controller.copyLastInsertedText()
            }
            .disabled(controller.lastInsertedText.isEmpty)

            Divider()

            Menu("Writing Mode: \(controller.writingMode.label)") {
                ForEach(WritingMode.allCases) { mode in
                    Button {
                        controller.writingMode = mode
                    } label: {
                        HStack {
                            Text(mode.label)
                            if controller.writingMode == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Divider()
            Button("Open DailyOps…") {
                MainWindow.show(controller: controller)
            }
            .keyboardShortcut("o")
            Button("Settings…") {
                MainWindow.show(controller: controller, selectedTab: .general)
            }
            .keyboardShortcut(",")
            Divider()
            Button("Quit DailyOps") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }

        Settings {
            SettingsView(controller: controller)
                .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    MainWindow.show(controller: controller, selectedTab: .general)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

private struct StatusMenuHeader: View {
    let controller: DictationController

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(AppBrand.displayName)
                .font(.headline)
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        if case .error(let message) = controller.state {
            return message
        }
        if !controller.hasMicPermission {
            return "Microphone permission needed"
        }
        if !controller.isReady {
            return "Accessibility permission needed"
        }
        switch controller.sttState {
        case .ready:
            return "Ready. Hold \(controller.hotkeyLabel) to dictate."
        case .loading:
            return "Preparing local speech model..."
        case .notLoaded:
            return "Speech model has not loaded yet"
        case .failed(let message):
            return "Speech model failed: \(message)"
        }
    }
}
