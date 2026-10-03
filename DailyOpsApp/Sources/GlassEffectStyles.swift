import SwiftUI

// MARK: - Glass Segment Option

public struct WFGlassSegmentOption<Value: Hashable>: Identifiable {
    public let id: Value
    public let title: String
    public let icon: String?

    public init(value: Value, title: String, icon: String? = nil) {
        self.id = value
        self.title = title
        self.icon = icon
    }
}

// MARK: - Native Apple Liquid Glass Segmented Control

/// A single continuous piece of translucent Apple Liquid Glass containing choices,
/// featuring a physical sliding glass selection surface with native spring physics,
/// interactive press depression, and full keyboard/VoiceOver accessibility.
public struct WFGlassSegmentedControl<Value: Hashable>: View {
    @Binding public var selection: Value
    public let options: [WFGlassSegmentOption<Value>]
    public var height: CGFloat = 28
    public var namespace: Namespace.ID

    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focusedIndex: Int?

    public init(
        selection: Binding<Value>,
        options: [WFGlassSegmentOption<Value>],
        height: CGFloat = 28,
        namespace: Namespace.ID
    ) {
        self._selection = selection
        self.options = options
        self.height = height
        self.namespace = namespace
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, opt in
                let isSelected = (opt.id == selection)
                SegmentButton(
                    option: opt,
                    isSelected: isSelected,
                    height: height,
                    colorScheme: colorScheme,
                    namespace: namespace,
                    action: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            selection = opt.id
                            focusedIndex = index
                        }
                    }
                )
                .focused($focusedIndex, equals: index)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(opt.title)
                .accessibilityValue(isSelected ? "Selected" : "")
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : [.isButton])
            }
        }
        .padding(2.5)
        .frame(height: height)
        .background {
            let outerShape = RoundedRectangle(cornerRadius: (height / 2), style: .continuous)
            ZStack {
                if #available(macOS 26.0, *) {
                    outerShape
                        .glassEffect()
                } else {
                    outerShape
                        .fill(.ultraThinMaterial)
                }

                // Neutral track surface
                outerShape
                    .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))

                outerShape
                    .strokeBorder(
                        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08),
                        lineWidth: 0.5
                    )
            }
        }
        .onKeyPress(.leftArrow) {
            selectPrevious()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            selectNext()
            return .handled
        }
    }

    private func selectPrevious() {
        guard let currentIdx = options.firstIndex(where: { $0.id == selection }), currentIdx > 0 else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
            selection = options[currentIdx - 1].id
            focusedIndex = currentIdx - 1
        }
    }

    private func selectNext() {
        guard let currentIdx = options.firstIndex(where: { $0.id == selection }), currentIdx < options.count - 1 else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
            selection = options[currentIdx + 1].id
            focusedIndex = currentIdx + 1
        }
    }
}

// MARK: - Segment Button with Interactive Press Physics

private struct SegmentButton<Value: Hashable>: View {
    let option: WFGlassSegmentOption<Value>
    let isSelected: Bool
    let height: CGFloat
    let colorScheme: ColorScheme
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon = option.icon {
                    Image(systemName: icon)
                        .font(.system(size: 10.5, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                }
                Text(option.title)
                    .font(.system(size: 11.5, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            }
            .padding(.horizontal, 9)
            .frame(height: height - 5)
            .contentShape(RoundedRectangle(cornerRadius: (height - 5) / 2, style: .continuous))
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isPressed)
        }
        .buttonStyle(PlainPressableButtonStyle(isPressed: $isPressed))
        .background {
            if isSelected {
                let innerShape = RoundedRectangle(cornerRadius: (height - 5) / 2, style: .continuous)
                ZStack {
                    if #available(macOS 26.0, *) {
                        innerShape
                            .glassEffect()
                    } else {
                        innerShape
                            .fill(.ultraThinMaterial)
                    }

                    // Native Apple active selection surface (neutral translucent glass)
                    innerShape
                        .fill(
                            colorScheme == .dark
                                ? Color.white.opacity(0.14)
                                : Color.white.opacity(0.72)
                        )

                    innerShape
                        .strokeBorder(
                            colorScheme == .dark
                                ? Color.white.opacity(0.20)
                                : Color.white.opacity(0.55),
                            lineWidth: 0.5
                        )
                }
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.08),
                    radius: 2,
                    x: 0,
                    y: 1
                )
                .matchedGeometryEffect(id: "liquid_glass_segment_active", in: namespace)
            }
        }
    }
}

// MARK: - Plain Pressable Button Style

private struct PlainPressableButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in
                isPressed = pressed
            }
    }
}

// MARK: - Native Apple Liquid Glass Metadata Badge

/// Subtle, quiet native material control for secondary metadata beside titles.
public struct WFGlassMetadataBadge: View {
    public let text: String

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7.5)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
    }
}
