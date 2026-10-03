import AppKit
import SwiftUI

enum MainTab: Hashable {
    case workspace
    case dictation
    case insights
    case dictionary
    case commandMode
    case formatting
    case privacy
    case general

    var title: String {
        switch self {
        case .workspace: "Workspace"
        case .dictation: "Dictation"
        case .insights: "Insights"
        case .dictionary: "Dictionary"
        case .commandMode: "Command Mode"
        case .formatting: "Smart Formatting"
        case .privacy: "Privacy"
        case .general: "General"
        }
    }

    var unselectedIcon: String {
        switch self {
        case .workspace: "sparkles"
        case .dictation: "mic"
        case .insights: "chart.bar"
        case .dictionary: "book"
        case .commandMode: "command.square"
        case .formatting: "wand.and.stars"
        case .privacy: "lock"
        case .general: "gearshape"
        }
    }

    var selectedIcon: String {
        switch self {
        case .workspace: "sparkles"
        case .dictation: "mic.fill"
        case .insights: "chart.bar.fill"
        case .dictionary: "book.fill"
        case .commandMode: "command.square.fill"
        case .formatting: "wand.and.stars.inverse"
        case .privacy: "lock.fill"
        case .general: "gearshape.fill"
        }
    }

    var icon: String {
        selectedIcon
    }

    var settingsPane: SettingsPane {
        switch self {
        case .workspace: .workspace
        case .dictation: .dictation
        case .insights: .insights
        case .dictionary: .dictionary
        case .commandMode: .commandMode
        case .formatting: .smartFormatting
        case .privacy: .privacy
        case .general: .general
        }
    }
}

@MainActor
@Observable
final class MainNavigation {
    var selectedTab: MainTab = .workspace
    var dictationSearch: String = ""
    var dictionarySearch: String = ""
    var showingDictionaryAdd: Bool = false
}

/// The app's main window: history and settings in one place. AppKit-managed
/// so it can be opened from the app delegate (Finder reopen) and the menu
/// bar alike.
@MainActor
enum MainWindow {
    private static var window: NSWindow?
    private static let navigation = MainNavigation()

    static func show(controller: DictationController, selectedTab: MainTab = .workspace) {
        NSApp.activate()
        navigation.selectedTab = selectedTab
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingController(rootView: MainView(controller: controller, navigation: navigation))
        let window = NSWindow(contentViewController: host)
        window.title = AppBrand.displayName
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.minSize = NSSize(width: 850, height: 600)
        window.setContentSize(NSSize(width: 1120, height: 740))
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
    }
}

struct MainView: View {
    let controller: DictationController
    @Bindable var navigation: MainNavigation
    @AppStorage("appearance") private var appearance = AppAppearance.system.rawValue

    var body: some View {
        HStack(spacing: 0) {
            DailyOpsSidebar(selectedTab: $navigation.selectedTab)

            Divider()
                .opacity(0.25)

            VStack(spacing: 0) {
                DailyOpsTitleBar(
                    selectedTab: navigation.selectedTab,
                    dictationSearch: $navigation.dictationSearch,
                    dictionarySearch: $navigation.dictionarySearch,
                    showingDictionaryAdd: $navigation.showingDictionaryAdd
                )

                Divider()
                    .opacity(0.25)

                SettingsView(
                    controller: controller,
                    pane: navigation.selectedTab.settingsPane,
                    dictationSearch: $navigation.dictationSearch,
                    dictionarySearch: $navigation.dictionarySearch,
                    showingDictionaryAdd: $navigation.showingDictionaryAdd
                )
                .modelContainer(controller.history.container)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(SettingsDesign.contentBackground)
        .frame(minWidth: 850, minHeight: 600)
        .tint(SettingsDesign.accentBlue)
        .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
    }
}

private struct DailyOpsSidebar: View {
    @Binding var selectedTab: MainTab
    @Namespace private var sidebarNamespace

    private let tabs: [MainTab] = [
        .workspace,
        .dictation,
        .insights,
        .dictionary,
        .commandMode,
        .formatting,
        .privacy,
        .general,
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with app icon and name
            HStack(spacing: 9) {
                DailyOpsBrandMark(size: 18)

                Text(AppBrand.displayName)
                    .font(SettingsDesign.brandingFont)
                    .foregroundStyle(Color.primary)
            }
            .padding(.horizontal, 16)
            .frame(height: SettingsDesign.sidebarHeaderHeight, alignment: .leading)

            Divider()
                .opacity(0.25)

            VStack(alignment: .leading, spacing: SettingsDesign.sidebarRowGap) {
                ForEach(tabs, id: \.self) { tab in
                    WFSidebarItem(
                        title: tab.title,
                        unselectedIcon: tab.unselectedIcon,
                        selectedIcon: tab.selectedIcon,
                        isSelected: selectedTab == tab,
                        namespace: sidebarNamespace,
                        action: {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                selectedTab = tab
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, SettingsDesign.sidebarHorizontalPadding)
            .padding(.top, 8)

            Spacer()
        }
        .padding(.vertical, 4)
        .frame(minWidth: 176, idealWidth: SettingsDesign.sidebarWidth, maxWidth: 196)
        .background(SettingsDesign.sidebarBackground)
    }
}

private struct DailyOpsTitleBar: View {
    let selectedTab: MainTab
    @Binding var dictationSearch: String
    @Binding var dictionarySearch: String
    @Binding var showingDictionaryAdd: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // Page title from MainWindow (Editorial Playfair Display Light)
            Text(selectedTab.title)
                .font(SettingsDesign.pageTitleFont)
                .foregroundStyle(Color.primary)

            Spacer(minLength: 16)

            // Header search bar for Dictation
            if selectedTab == .dictation {
                WFSearchField(text: $dictationSearch, placeholder: "Search dictations...")
            } else if selectedTab == .dictionary {
                HStack(spacing: 10) {
                    WFSearchField(text: $dictionarySearch, placeholder: "Search dictionary...")

                    Button {
                        showingDictionaryAdd = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                            Text("Add Word")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .padding(.horizontal, 14)
                        .frame(height: SettingsDesign.searchHeight)
                        .background(SettingsDesign.accentBlue, in: Capsule())
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, SettingsDesign.contentHorizontalMargin)
        .frame(height: SettingsDesign.pageHeaderHeight)
        .background(SettingsDesign.contentBackground)
    }
}
