import SwiftUI

/// Reusable native macOS command confirmation component.
///
/// Presents pending confirmation requests (WhatsApp, App Quit, Clipboard Clear, etc.)
/// with clear visual hierarchy, keyboard shortcuts (Escape = cancel, Return = confirm),
/// and clean macOS materials without artificial AI glowing effects.
struct CommandConfirmationBar: View {
    let request: ConfirmationRequest
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var riskColor: Color {
        switch request.risk {
        case .destructive:
            return Color(red: 1.0, green: 0.35, blue: 0.32)
        case .sensitive, .safe:
            return Color.wesleyBlue
        }
    }

    var iconName: String {
        Self.iconName(for: request.plan.steps.first?.intent.identifier)
    }

    static func iconName(for identifier: CommandIdentifier?) -> String {
        switch identifier {
        case .whatsAppSendMessage:
            return "message.fill"
        case .whatsAppOpenChat:
            return "message"
        case .appQuit:
            return "xmark.circle.fill"
        case .appOpen, .appSwitch:
            return "app.badge"
        case .appHide:
            return "eye.slash.fill"
        case .clipboardClear:
            return "trash.fill"
        case .clipboardCopyLast:
            return "doc.on.doc.fill"
        case .calendarCreateEvent, .calendarListEvents, .calendarOpen:
            return "calendar.badge.plus"
        case .remindersCreate, .remindersList, .remindersOpen:
            return "checklist"
        case .notesCreate, .notesOpen:
            return "note.text.badge.plus"
        case .finderOpenLocation, .finderFindFiles:
            return "folder.fill"
        case .browserOpenPrivate:
            return "lock.shield.fill"
        case .browserOpenURL, .browserSearch, .browserOpenDefault:
            return "globe"
        default:
            return "questionmark.circle.fill"
        }
    }

    private var displayMessage: String {
        if request.plan.steps.first?.intent.identifier == .whatsAppSendMessage {
            if let range = request.details.range(of: "Message: \"") {
                let candidate = String(request.details[range.upperBound...])
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                return "“\(candidate)”"
            }
        }
        return request.details
    }

    private var confirmButtonTitle: String {
        request.confirmActionLabel
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // Leading icon badge
            ZStack {
                Circle()
                    .fill(riskColor.opacity(0.18))
                    .frame(width: 30, height: 30)
                Image(systemName: iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(riskColor)
            }

            // Central content: Title, Subtitle (Recipient), Details (Message body)
            VStack(alignment: .leading, spacing: 3) {
                Text(request.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let subtitle = request.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                }

                if !displayMessage.isEmpty {
                    Text(displayMessage)
                        .font(.system(size: 12, weight: .regular))
                        .italic()
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: 340, alignment: .leading)

            Spacer(minLength: 12)

            // Trailing action buttons
            HStack(spacing: 8) {
                Button(action: onCancel) {
                    Text(request.cancelActionLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.12))
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                        }
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Cancel (Escape)")
                .accessibilityLabel(request.cancelActionLabel)

                Button(action: onConfirm) {
                    Text(confirmButtonTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(request.risk == .destructive ? Color.red.opacity(0.85) : Color.wesleyBlue)
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .help("\(confirmButtonTitle) (Return)")
                .accessibilityLabel(confirmButtonTitle)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .frame(maxWidth: 580)
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }
}
