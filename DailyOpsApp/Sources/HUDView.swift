import SwiftUI

/// The Native Apple Liquid Glass Transcription HUD:
/// A restrained, compact glass control whose material itself responds to interaction.
/// Features subtle physical expansion on activation, subtle material depth driven by
/// real microphone RMS, and clean Apple system typography without decorative visualizers or gradients.
struct HUDView: View {
    let controller: DictationController
    let onHeightChange: ((CGFloat) -> Void)?
    @AppStorage("hudGlassOpacity") private var glassOpacity = 0.85
    @Environment(\.colorScheme) private var colorScheme

    init(controller: DictationController, onHeightChange: ((CGFloat) -> Void)? = nil) {
        self.controller = controller
        self.onHeightChange = onHeightChange
    }

    var body: some View {
        let isRecording = (controller.state == .recording)
        let rawLevel = isRecording ? controller.recorder.level : 0.0
        let rms = CGFloat(min(1.0, max(0.0, rawLevel * 6.0)))

        // Physical material response: resting height 38pt, expanding to 44pt when listening/recording + subtle RMS breathing
        let baseHeight: CGFloat = controller.state.isConfirming ? 78 : (isRecording ? 44 : 38)
        let dynamicHeight: CGFloat = controller.state.isConfirming ? 78 : (baseHeight + rms * 2.0)
        let cornerRadius: CGFloat = dynamicHeight / 2

        HStack(spacing: 9) {
            content(isRecording: isRecording, rms: rms)
        }
        .padding(.horizontal, isRecording ? 16 + rms * 2.0 : 14)
        .frame(height: controller.state.isConfirming ? nil : dynamicHeight)
        .background {
            AppleLiquidGlassContainer(
                cornerRadius: cornerRadius,
                rms: rms,
                isRecording: isRecording,
                opacity: glassOpacity,
                colorScheme: colorScheme
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { onHeightChange?(proxy.size.height) }
                    .onChange(of: proxy.size.height) { _, newHeight in
                        onHeightChange?(newHeight)
                    }
            }
        )
        .animation(.spring(response: 0.30, dampingFraction: 0.82), value: controller.state)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func content(isRecording: Bool, rms: CGFloat) -> some View {
        switch controller.state {
        case .idle:
            Image(systemName: "mic.fill")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Microphone idle")

        case .recording:
            Image(systemName: "mic.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SettingsDesign.accentBlue)
                .offset(y: -rms * 1.2)
                .accessibilityLabel("Microphone active")

            if controller.live.hasText {
                HStack(spacing: 8) {
                    WFRealAudioWaveformView(level: CGFloat(controller.recorder.level), rms: rms, compact: true)
                    LiveTranscriptLabel(live: controller.live)
                }
            } else {
                WFRealAudioWaveformView(level: CGFloat(controller.recorder.level), rms: rms, compact: false)
                    .transition(.opacity)
            }

        case .transcribing:
            ProgressView()
                .controlSize(.small)
            Text("Transcribing…")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.primary)

        case .processing, .cleaning:
            ProgressView()
                .controlSize(.small)
            Text(controller.writingMode == .formal ? "Formal Rewrite…" : "Formatting…")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.primary)

        case .inserting:
            ProgressView()
                .controlSize(.small)
            Text("Pasting…")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.primary)

        case .polishing(let action):
            ProgressView()
                .controlSize(.small)
            Image(systemName: "wand.and.sparkles")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(SettingsDesign.accentBlue)
            Text(action.isEmpty ? "Writing Tools…" : action)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.primary)

        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(SettingsDesign.accentBlue)
            Text(controller.lastInsertedText)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 320)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))

        case .error(let message):
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.red)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: 320)

        case .confirming(let request):
            CommandConfirmationBar(
                request: request,
                onConfirm: { controller.confirmPending(id: request.id) },
                onCancel: { controller.cancelPending(id: request.id) }
            )
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Native Apple Liquid Glass Background Container

private struct AppleLiquidGlassContainer: View {
    let cornerRadius: CGFloat
    let rms: CGFloat
    let isRecording: Bool
    let opacity: Double
    let colorScheme: ColorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            if #available(macOS 26.0, *) {
                shape
                    .glassEffect()
            } else {
                shape
                    .fill(.ultraThinMaterial)
            }

            // Neutral material depth tint that adapts to theme and subtly deepens with RMS
            shape
                .fill(
                    colorScheme == .dark
                        ? Color(white: 0.12).opacity((0.36 + Double(rms) * 0.12) * min(max(opacity, 0.4), 1.0))
                        : Color.white.opacity((0.48 + Double(rms) * 0.10) * min(max(opacity, 0.4), 1.0))
                )

            // Very thin, subtle edge definition
            shape
                .strokeBorder(
                    colorScheme == .dark
                        ? Color.white.opacity(0.14 + Double(rms) * 0.10)
                        : Color.black.opacity(0.08 + Double(rms) * 0.05),
                    lineWidth: 0.65
                )
        }
        // Native system drop shadow with subtle depth expansion
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? (0.24 + Double(rms) * 0.06) : 0.10),
            radius: isRecording ? 14 + rms * 3 : 10,
            x: 0,
            y: isRecording ? 4 + rms * 1.5 : 3
        )
    }
}

// MARK: - Live Partial Transcript Label

private struct LiveTranscriptLabel: View {
    let live: LiveTranscript

    var body: some View {
        Text(live.text)
            .font(.system(size: 12.5, weight: .regular))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.head)
            .frame(maxWidth: 320, alignment: .trailing)
            .transition(.opacity)
            .accessibilityLabel("Live transcript")
            .accessibilityValue(live.text)
    }
}

// MARK: - Native Apple Real-Audio Waveform Visualization

private struct WFRealAudioWaveformView: View {
    let level: CGFloat
    let rms: CGFloat
    var compact: Bool = false

    var body: some View {
        let barCount = compact ? 3 : 5
        let barWeights: [CGFloat] = compact ? [0.65, 1.0, 0.75] : [0.55, 0.85, 1.0, 0.80, 0.50]

        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                let weight = barWeights[index]
                // Resting baseline height 4.5pt; scales smoothly with real mic level up to 15pt
                let clampedLevel = min(1.0, max(0.0, level * 5.0))
                let dynamicHeight = 4.5 + clampedLevel * 10.5 * weight

                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(SettingsDesign.accentBlue.opacity(0.70 + Double(clampedLevel) * 0.30))
                    .frame(width: 2.5, height: dynamicHeight)
                    .animation(.interactiveSpring(response: 0.14, dampingFraction: 0.78), value: dynamicHeight)
            }
        }
        .frame(height: 16)
        .accessibilityLabel("Audio input waveform")
    }
}
