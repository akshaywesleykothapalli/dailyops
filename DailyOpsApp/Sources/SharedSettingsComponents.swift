import SwiftUI

// MARK: - Grouped Section Container

/// A native macOS grouped settings section with an optional uppercase title
/// and rounded container with hairline borders.
struct WFSection<Content: View>: View {
    let title: String?
    let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .sectionHeaderStyle()
                    .padding(.leading, 4)
            }

            VStack(spacing: 0) {
                content
            }
            .background(SettingsDesign.groupBackground, in: RoundedRectangle(cornerRadius: SettingsDesign.groupCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: SettingsDesign.groupCornerRadius)
                    .strokeBorder(SettingsDesign.separatorColor, lineWidth: 1)
            }
        }
    }
}

// MARK: - Row Divider

struct WFRowDivider: View {
    var leadingInset: CGFloat = SettingsDesign.rowHorizontalPadding

    var body: some View {
        Divider()
            .opacity(0.4)
            .padding(.leading, leadingInset)
    }
}

// MARK: - Native macOS Settings Row

/// Standard native settings row: Title + Description on leading side, Control on trailing side.
struct WFRow<Control: View>: View {
    let title: String
    let description: String?
    let control: Control

    init(_ title: String, description: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.description = description
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SettingsDesign.bodyFontMedium)
                    .foregroundStyle(Color.primary)

                if let description {
                    Text(description)
                        .font(SettingsDesign.captionFont)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 16)

            control
        }
        .padding(.horizontal, SettingsDesign.rowHorizontalPadding)
        .padding(.vertical, SettingsDesign.rowVerticalPadding)
    }
}

// MARK: - Toggle Row

struct WFToggleRow: View {
    let title: String
    let description: String?
    @Binding var isOn: Bool

    init(_ title: String, description: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.description = description
        self._isOn = isOn
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SettingsDesign.bodyFontMedium)
                    .foregroundStyle(Color.primary)

                if let description {
                    Text(description)
                        .font(SettingsDesign.captionFont)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 16)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, SettingsDesign.rowHorizontalPadding)
        .padding(.vertical, SettingsDesign.rowVerticalPadding)
    }
}

// MARK: - Info / Labeled Content Row

struct WFInfoRow: View {
    let title: String
    let description: String?
    let value: String
    var selectable: Bool = false

    init(_ title: String, description: String? = nil, value: String, selectable: Bool = false) {
        self.title = title
        self.description = description
        self.value = value
        self.selectable = selectable
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SettingsDesign.bodyFontMedium)
                    .foregroundStyle(Color.primary)

                if let description {
                    Text(description)
                        .font(SettingsDesign.captionFont)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 16)

            if selectable {
                Text(value)
                    .font(SettingsDesign.bodyFont)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                Text(value)
                    .font(SettingsDesign.bodyFont)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, SettingsDesign.rowHorizontalPadding)
        .padding(.vertical, SettingsDesign.rowVerticalPadding)
    }
}

// MARK: - Button Row

struct WFButtonRow: View {
    let title: String
    let description: String?
    let buttonLabel: String
    let systemImage: String?
    let role: ButtonRole?
    let tint: Color?
    let action: () -> Void

    init(
        _ title: String,
        description: String? = nil,
        buttonLabel: String,
        systemImage: String? = nil,
        role: ButtonRole? = nil,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.description = description
        self.buttonLabel = buttonLabel
        self.systemImage = systemImage
        self.role = role
        self.tint = tint
        self.action = action
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SettingsDesign.bodyFontMedium)
                    .foregroundStyle(role == .destructive ? Color.red : Color.primary)

                if let description {
                    Text(description)
                        .font(SettingsDesign.captionFont)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 16)

            Button(role: role, action: action) {
                if let systemImage {
                    Label(buttonLabel, systemImage: systemImage)
                } else {
                    Text(buttonLabel)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .tint(tint ?? (role == .destructive ? .red : SettingsDesign.accentBlue))
        }
        .padding(.horizontal, SettingsDesign.rowHorizontalPadding)
        .padding(.vertical, SettingsDesign.rowVerticalPadding)
    }
}

// MARK: - Compact Metric Tile for Insights

struct WFMetricTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(SettingsDesign.metricValueFont)
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(title)
                .font(SettingsDesign.metricLabelFont)
                .foregroundStyle(SettingsDesign.secondaryText)
                .textCase(.uppercase)
                .tracking(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(height: SettingsDesign.metricTileHeight)
        .background(SettingsDesign.controlBackground, in: RoundedRectangle(cornerRadius: SettingsDesign.metricTileRadius))
        .overlay {
            RoundedRectangle(cornerRadius: SettingsDesign.metricTileRadius)
                .strokeBorder(SettingsDesign.separatorColor, lineWidth: 1)
        }
    }
}

// MARK: - Reusable Search Field Capsule

struct WFSearchField: View {
    @Binding var text: String
    let placeholder: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(isFocused ? SettingsDesign.accentBlue : Color.secondary)
                .frame(width: 16)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .regular))
                .focused($isFocused)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.secondary.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(width: SettingsDesign.searchWidth, height: SettingsDesign.searchHeight)
        .background(
            Capsule()
                .fill(SettingsDesign.controlBackground)
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    isFocused ? SettingsDesign.accentBlue : SettingsDesign.separatorColor,
                    lineWidth: isFocused ? 1.5 : 1
                )
        )
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Reusable Sidebar Item with Smooth Moving Selection

struct WFSidebarItem: View {
    let title: String
    let unselectedIcon: String
    let selectedIcon: String
    let isSelected: Bool
    var namespace: Namespace.ID
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: SettingsDesign.sidebarIconGap) {
                // Fixed-width icon container
                ZStack {
                    Image(systemName: isSelected ? selectedIcon : unselectedIcon)
                        .font(.system(size: SettingsDesign.sidebarIconSize, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(iconColor)
                }
                .frame(width: SettingsDesign.sidebarIconContainerSize, height: SettingsDesign.sidebarIconContainerSize)

                Text(title)
                    .font(isSelected ? SettingsDesign.navigationFontSelected : SettingsDesign.navigationFont)
                    .foregroundStyle(labelColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 18)
            .padding(.trailing, 10)
            .frame(height: SettingsDesign.sidebarRowHeight)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: SettingsDesign.sidebarCornerRadius)
                        .fill(SettingsDesign.selectedItemBackground)
                        .matchedGeometryEffect(id: "sidebar_active_bg", in: namespace)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: SettingsDesign.sidebarCornerRadius)
                        .fill(SettingsDesign.hoverBackground)
                }
            }
            .overlay(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: SettingsDesign.indicatorCornerRadius)
                        .fill(SettingsDesign.indicatorColor)
                        .frame(width: SettingsDesign.indicatorWidth, height: SettingsDesign.indicatorHeight)
                        .matchedGeometryEffect(id: "sidebar_active_indicator", in: namespace)
                        .padding(.leading, 3)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: SettingsDesign.sidebarCornerRadius))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var iconColor: Color {
        if colorScheme == .dark {
            return isSelected ? SettingsDesign.accentBlue : SettingsDesign.accentBlue.opacity(0.70)
        } else {
            return isSelected ? SettingsDesign.accentBlue : SettingsDesign.accentBlue.opacity(0.85)
        }
    }

    private var labelColor: Color {
        if colorScheme == .dark {
            return isSelected ? Color.white : Color(white: 0.82)
        } else {
            return isSelected ? Color(red: 0.12, green: 0.12, blue: 0.13) : Color(red: 0.22, green: 0.23, blue: 0.25)
        }
    }
}

// MARK: - Reusable Preference Picker (Native Apple Settings Style)

struct WFPreferencePickerOption<Value: Hashable>: Identifiable {
    let id: Value
    let title: String
    let icon: String?

    init(value: Value, title: String, icon: String? = nil) {
        self.id = value
        self.title = title
        self.icon = icon
    }
}

struct WFPreferencePicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [WFPreferencePickerOption<Value>]
    var minWidth: CGFloat = 110
    var maxWidth: CGFloat? = nil
    var onChange: ((Value) -> Void)? = nil

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    private var selectedOption: WFPreferencePickerOption<Value>? {
        options.first(where: { $0.id == selection })
    }

    private var selectedTitle: String {
        selectedOption?.title ?? "\(selection)"
    }

    private var selectedIcon: String? {
        selectedOption?.icon
    }

    var body: some View {
        Menu {
            ForEach(options) { opt in
                Button {
                    selection = opt.id
                    onChange?(opt.id)
                } label: {
                    HStack {
                        if let icon = opt.icon {
                            Image(systemName: icon)
                        }
                        Text(opt.title)
                        if opt.id == selection {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if let icon = selectedIcon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(SettingsDesign.secondaryText)
                }

                Text(selectedTitle)
                    .font(SettingsDesign.controlFont)
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(SettingsDesign.secondaryText.opacity(0.85))
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .frame(minWidth: minWidth)
            .frame(maxWidth: maxWidth)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovered ? SettingsDesign.hoverBackground : SettingsDesign.controlBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isHovered
                            ? SettingsDesign.separatorColor.opacity(0.8)
                            : SettingsDesign.separatorColor.opacity(0.4),
                        lineWidth: 0.75
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: maxWidth == nil, vertical: true)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Reusable Dropdown Container

struct WFDropdownContainer<Content: View>: View {
    let width: CGFloat
    let content: Content

    @State private var isHovered = false

    init(width: CGFloat = 200, @ViewBuilder content: () -> Content) {
        self.width = width
        self.content = content()
    }

    var body: some View {
        content
            .labelsHidden()
            .pickerStyle(.menu)
            .font(SettingsDesign.controlFont)
            .padding(.horizontal, 6)
            .frame(width: width, height: SettingsDesign.dropdownHeight)
            .background(SettingsDesign.controlBackground, in: RoundedRectangle(cornerRadius: SettingsDesign.dropdownRadius))
            .overlay(
                RoundedRectangle(cornerRadius: SettingsDesign.dropdownRadius)
                    .strokeBorder(isHovered ? SettingsDesign.separatorColor.opacity(0.9) : SettingsDesign.separatorColor, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: SettingsDesign.dropdownRadius))
            .onHover { isHovered = $0 }
    }
}