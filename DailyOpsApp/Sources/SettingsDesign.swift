import AppKit
import SwiftUI

// MARK: - Settings Pane Enum

enum SettingsPane: String, CaseIterable, Identifiable {
    case workspace = "Workspace"
    case dictation = "Dictation"
    case insights = "Insights"
    case dictionary = "Dictionary"
    case workSetups = "Work Setups"
    case commandMode = "Command Mode"
    case smartFormatting = "Smart Formatting"
    case privacy = "Privacy"
    case general = "General"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .workspace: "sparkles"
        case .dictation: "mic"
        case .insights: "chart.bar"
        case .dictionary: "book"
        case .workSetups: "desktopcomputer"
        case .commandMode: "command.square"
        case .smartFormatting: "wand.and.stars"
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
        case .workSetups: "desktopcomputer"
        case .commandMode: "command.square.fill"
        case .smartFormatting: "wand.and.stars.inverse"
        case .privacy: "lock.fill"
        case .general: "gearshape.fill"
        }
    }
}

// MARK: - DailyOps Settings Design System

/// Central design tokens for the DailyOps macOS UI.
/// Playfair Display Light for editorial/display hierarchy, SF Pro for functional UI,
/// refined Apple-style continuous corner curves, and neutral surface hierarchy.
struct SettingsDesign {

    // MARK: - Color System (Adaptive Neutral Hierarchy with Blue Accent)

    /// The primary accent blue used throughout the application (#3157E8).
    static let accentBlue = Color(red: 0.192, green: 0.341, blue: 0.910)

    /// Selected sidebar item background - neutral charcoal in dark mode, subtle blue tint in light mode.
    static let selectedItemBackground = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(white: 0.17, alpha: 1.0)
            : NSColor(red: 0.19, green: 0.34, blue: 0.91, alpha: 0.07)
    })

    /// Hover background for interactive rows/items.
    static let hoverBackground = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(white: 1.0, alpha: 0.04)
            : NSColor(white: 0.0, alpha: 0.035)
    })

    /// Adaptive application canvas background (Level 0)
    /// Light: #F6F6F4 (soft off-white paper), Dark: #181818 (neutral dark charcoal, no blue cast)
    static let contentBackground = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(red: 0.094, green: 0.094, blue: 0.094, alpha: 1.0)
            : NSColor(red: 0.965, green: 0.965, blue: 0.957, alpha: 1.0)
    })

    /// Adaptive sidebar background
    /// Light: #F3F3F1, Dark: #151515 (slightly darker neutral charcoal, no blue cast)
    static let sidebarBackground = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(red: 0.082, green: 0.082, blue: 0.082, alpha: 1.0)
            : NSColor(red: 0.953, green: 0.953, blue: 0.945, alpha: 1.0)
    })

    /// Adaptive control / input / selector surface (Level 1)
    /// Light: #FFFFFF, Dark: #202020 (neutral charcoal, no blue cast)
    static let controlBackground = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(red: 0.125, green: 0.125, blue: 0.125, alpha: 1.0)
            : NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
    })

    /// Grouped section container background (Secondary surface)
    /// Light: #FFFFFF with subtle opacity, Dark: #242424 (neutral charcoal, no blue cast)
    static let groupBackground = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(red: 0.141, green: 0.141, blue: 0.141, alpha: 1.0)
            : NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.72)
    })

    /// Primary text color
    /// Light: #202124, Dark: #F2F2F2
    static let primaryText = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1.0)
            : NSColor(red: 0.125, green: 0.13, blue: 0.14, alpha: 1.0)
    })

    /// Secondary text color
    /// Light: #69717C, Dark: muted neutral gray #8E8E93 (no blue cast)
    static let secondaryText = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(red: 0.56, green: 0.56, blue: 0.58, alpha: 1.0)
            : NSColor(red: 0.41, green: 0.44, blue: 0.49, alpha: 1.0)
    })

    /// Hairline separator color
    /// Light: subtle gray #D9DADD, Dark: very subtle neutral gray (no blue cast)
    static let separatorColor = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(white: 1.0, alpha: 0.08)
            : NSColor(red: 0.82, green: 0.83, blue: 0.85, alpha: 0.65)
    })

    /// Subtle divider
    static let divider = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(white: 1.0, alpha: 0.06)
            : NSColor(red: 0.84, green: 0.85, blue: 0.86, alpha: 0.50)
    })

    /// Selected sidebar item indicator color
    static let indicatorColor = accentBlue

    // MARK: - Typography (Playfair Display Light for Editorial, SF Pro for Functional UI)

    /// Page title in global header: Playfair Display Light, 31pt.
    static let pageTitleFont = Font.custom("Playfair Display", size: 31).weight(.light)
    static let editorialTitleFont = Font.custom("Playfair Display", size: 31).weight(.light)

    /// Large section heading: Playfair Display Light, 19.5pt.
    static let sectionHeadingFont = Font.custom("Playfair Display", size: 19.5).weight(.light)
    static let editorialSectionFont = Font.custom("Playfair Display", size: 19.5).weight(.light)

    /// Section heading: Native macOS small header style, 13pt semibold SF Pro.
    static let sectionTitleFont = Font.system(size: 13, weight: .semibold, design: .default)

    /// Body / label text: SF Pro 13pt.
    static let bodyFont = Font.system(size: 13, weight: .regular, design: .default)
    static let bodyFontMedium = Font.system(size: 13, weight: .medium, design: .default)
    static let bodyFontSemibold = Font.system(size: 13, weight: .semibold, design: .default)

    /// Secondary description / caption text: SF Pro 11.5pt.
    static let captionFont = Font.system(size: 11.5, weight: .regular, design: .default)
    static let captionFontMedium = Font.system(size: 11.5, weight: .medium, design: .default)
    static let secondaryFont = Font.system(size: 11.5, weight: .regular, design: .default)

    /// Control font for dropdowns and pickers: SF Pro 13pt.
    static let controlFont = Font.system(size: 13, weight: .regular, design: .default)

    /// Sidebar navigation item labels: SF Pro 13.5pt.
    static let navigationFont = Font.system(size: 13.5, weight: .regular, design: .default)
    static let navigationFontSelected = Font.system(size: 13.5, weight: .semibold, design: .default)

    /// Metric value: Playfair Display 28pt medium for Insights metric tiles (stronger than titles).
    static let metricValueFont = Font.custom("Playfair Display", size: 28).weight(.medium)

    /// Metric label: SF Pro uppercase, tracked, 10.5pt.
    static let metricLabelFont = Font.system(size: 10.5, weight: .semibold, design: .default)

    /// Small UI labels / badges.
    static let smallLabelFont = Font.system(size: 11, weight: .regular, design: .default)
    static let smallLabelFontMedium = Font.system(size: 11, weight: .medium, design: .default)

    /// Command syntax: monospaced 12.5pt.
    static let commandSyntaxFont = Font.system(size: 12.5, weight: .medium, design: .monospaced)
    static let commandSyntaxFontSmall = Font.system(size: 11, weight: .medium, design: .monospaced)
    static let technicalFont = Font.system(size: 12.5, weight: .medium, design: .monospaced)

    /// App branding in sidebar: 14.5pt semibold.
    static let brandingFont = Font.system(size: 14.5, weight: .semibold, design: .default)
    static let brandingIconSize: CGFloat = 18

    /// Dictation row typography: SF Pro
    static let dictationTextFont = Font.system(size: 13, weight: .regular, design: .default)
    static let dictationTimeFont = Font.system(size: 11.5, weight: .medium, design: .monospaced)
    static let dictationMetaFont = Font.system(size: 11.5, weight: .medium, design: .default)

    // MARK: - Spacing Scale (Native macOS Compact Density)

    static let sectionSpacing: CGFloat = 24
    static let groupSpacing: CGFloat = 14
    static let rowVerticalPadding: CGFloat = 8
    static let rowHorizontalPadding: CGFloat = 16
    static let contentHorizontalMargin: CGFloat = 30
    static let contentVerticalPadding: CGFloat = 20
    static let pageHeaderHeight: CGFloat = 68

    /// Sidebar dimensions (spacious vertically ~42pt, compact horizontally ~184pt)
    static let sidebarWidth: CGFloat = 184
    static let sidebarHeaderHeight: CGFloat = 48
    static let sidebarRowHeight: CGFloat = 42
    static let sidebarRowGap: CGFloat = 4.5
    static let sidebarHorizontalPadding: CGFloat = 8
    static let sidebarIconContainerSize: CGFloat = 20
    static let sidebarIconSize: CGFloat = 16
    static let sidebarIconGap: CGFloat = 9

    // MARK: - Apple-Style Continuous Corner Geometry System

    /// Small controls, badges, tags: 8–10pt
    static let smallControlRadius: CGFloat = 8
    static let smallCornerRadius: CGFloat = 8

    /// Dropdown menus / pickers: 10–12pt
    static let dropdownRadius: CGFloat = 10
    static let mediumCornerRadius: CGFloat = 10

    /// Sidebar selected background: 10–12pt
    static let sidebarCornerRadius: CGFloat = 10

    /// Medium controls: 12–14pt
    static let mediumControlRadius: CGFloat = 12

    /// Cards / Metric tiles / Shortcut cards: 14–16pt
    static let cardRadius: CGFloat = 15
    static let standardCardRadius: CGFloat = 15
    static let metricTileRadius: CGFloat = 16
    static let shortcutCardRadius: CGFloat = 15

    /// Large grouped surfaces / sections: 16–18pt
    static let groupCornerRadius: CGFloat = 16
    static let largeGroupRadius: CGFloat = 16

    /// Heatmap container & cells
    static let heatmapContainerRadius: CGFloat = 15
    static let heatmapCellRadius: CGFloat = 3.5

    /// Sidebar selection indicator: 2.5pt width, 22pt height, 1.25pt radius
    static let indicatorWidth: CGFloat = 2.5
    static let indicatorHeight: CGFloat = 22
    static let indicatorCornerRadius: CGFloat = 1.25

    // MARK: - Control Heights & Dimensions

    static let dropdownHeight: CGFloat = 32
    static let themeSelectorHeight: CGFloat = 32
    static let shortcutCardHeight: CGFloat = 52
    static let metricTileHeight: CGFloat = 96
    static let searchHeight: CGFloat = 32
    static let searchWidth: CGFloat = 200
    static let searchCornerRadius: CGFloat = 16
    static let primaryButtonHeight: CGFloat = 32
    static let primaryButtonRadius: CGFloat = 16

    /// Dictation Row Dimensions
    static let dictationTimeWidth: CGFloat = 76
    static let dictationActionSize: CGFloat = 14
    static let dictationRowVerticalPadding: CGFloat = 6
    static let dictationRowHorizontalPadding: CGFloat = 10
}

// MARK: - Shared Hover & Elevation System

/// ONE reusable SwiftUI-native subtle hover modifier.
/// Native macOS style: faint background tint only, no shadow, no scale, no vertical translation.
struct WFHoverElevationModifier: ViewModifier {
    var cornerRadius: CGFloat = 8
    var isInteractive: Bool = true

    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background {
                if isHovered && isInteractive {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(SettingsDesign.hoverBackground)
                }
            }
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { hovering in
                guard isInteractive else { return }
                isHovered = hovering
            }
    }
}

// MARK: - View Modifiers & Extensions

extension View {
    /// Applies the shared subtle hover tint without changing layout dimensions.
    func wfHoverElevation(cornerRadius: CGFloat = 8, isInteractive: Bool = true) -> some View {
        modifier(WFHoverElevationModifier(cornerRadius: cornerRadius, isInteractive: isInteractive))
    }

    /// Section header label style
    func sectionHeaderStyle() -> some View {
        self
            .font(SettingsDesign.sectionTitleFont)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.6)
    }

    /// Major section heading style (Editorial Playfair Display Light)
    func majorSectionHeaderStyle() -> some View {
        self
            .font(SettingsDesign.sectionHeadingFont)
            .foregroundStyle(Color.primary)
    }

    /// Caption text style
    func captionTextStyle() -> some View {
        self
            .font(SettingsDesign.captionFont)
            .foregroundStyle(.secondary)
    }
}
