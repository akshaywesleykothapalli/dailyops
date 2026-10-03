import SwiftData
import SwiftUI

struct DictationPane: View {
    @Bindable var controller: DictationController
    @Binding var search: String

    @Query(sort: \DictationEntry.date, order: .reverse) private var entries: [DictationEntry]
    @Environment(\.modelContext) private var context

    @State private var deleteErrorMessage: String?
    @State private var entryToDelete: DictationEntry?
    @State private var showingDeleteConfirmation = false

    init(controller: DictationController, search: Binding<String> = .constant("")) {
        self.controller = controller
        _search = search
    }

    var body: some View {
        let sections = HistoryGrouping.sections(from: entries, matching: search)

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(sections) { section in
                    Section {
                        VStack(spacing: 0) {
                            ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                                if index > 0 {
                                    Divider()
                                        .opacity(0.2)
                                        .padding(.leading, SettingsDesign.contentHorizontalMargin + SettingsDesign.dictationTimeWidth + 14)
                                        .padding(.trailing, SettingsDesign.contentHorizontalMargin)
                                }
                                DictationRow(
                                    entry: row.entry,
                                    time: row.time,
                                    entryToDelete: $entryToDelete,
                                    showingDeleteConfirmation: $showingDeleteConfirmation
                                )
                                .padding(.horizontal, SettingsDesign.contentHorizontalMargin)
                            }
                        }
                        .padding(.bottom, 12)
                    } header: {
                        DictationSectionHeader(title: section.title, wordCountText: section.formattedWordCount)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .background(SettingsDesign.contentBackground)
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No Dictations Yet",
                    systemImage: "waveform",
                    description: Text("Hold your push-to-talk key anywhere to dictate. Your recent speech and commands will appear here.")
                )
            } else if sections.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .alert("Error Deleting Dictation", isPresented: Binding(
            get: { deleteErrorMessage != nil },
            set: { if !$0 { deleteErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { deleteErrorMessage = nil }
        } message: {
            if let error = deleteErrorMessage {
                Text(error)
            }
        }
        .alert("Delete Transcription?", isPresented: $showingDeleteConfirmation, presenting: entryToDelete) { entry in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                withAnimation(.easeOut(duration: 0.18)) {
                    context.delete(entry)
                }
                do {
                    try context.save()
                } catch {
                    log.error("Could not delete dictation: \(error.localizedDescription)")
                    deleteErrorMessage = "Could not delete: \(error.localizedDescription)"
                }
            }
        } message: { _ in
            Text("This entry will be permanently removed from your dictations.")
        }
    }
}

// MARK: - Day Section Header

private struct DictationSectionHeader: View {
    let title: String
    let wordCountText: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)

            Spacer()

            WFGlassMetadataBadge(text: wordCountText)
        }
        .padding(.horizontal, SettingsDesign.contentHorizontalMargin)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            Rectangle()
                .fill(SettingsDesign.contentBackground)
                .overlay(alignment: .bottom) {
                    Divider().opacity(0.25)
                }
        )
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Dictation Row with Native macOS Hover Interaction

private enum CopyFeedbackState: Equatable {
    case idle
    case copied
    case failed
}

private struct DictationRow: View {
    let entry: DictationEntry
    let time: String
    @Binding var entryToDelete: DictationEntry?
    @Binding var showingDeleteConfirmation: Bool

    @State private var showRaw = false
    @State private var isHovered = false
    @State private var copyState: CopyFeedbackState = .idle
    @State private var copyResetTask: Task<Void, Never>?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // REGION 1: Fixed Time Column
            Text(time)
                .font(SettingsDesign.dictationTimeFont)
                .foregroundStyle(.secondary)
                .frame(width: SettingsDesign.dictationTimeWidth, alignment: .trailing)
                .padding(.top, 2)

            // REGION 2: Flexible Content Column
            VStack(alignment: .leading, spacing: 4) {
                if entry.isCommand {
                    HStack(spacing: 4) {
                        Image(systemName: "command")
                            .font(.system(size: 9, weight: .bold))
                        Text("COMMAND")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.5)
                    }
                    .foregroundStyle(SettingsDesign.accentBlue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(SettingsDesign.accentBlue.opacity(0.10), in: RoundedRectangle(cornerRadius: 3))
                }

                Text(showRaw ? entry.raw : (entry.isCommand ? (entry.commandSummary ?? entry.cleaned) : entry.cleaned))
                    .font(SettingsDesign.dictationTextFont)
                    .foregroundStyle(Color.primary)
                    .lineLimit(showRaw ? nil : 2)
                    .lineSpacing(2)
                    .textSelection(.enabled)

                if shouldShowMore || !entry.appName.isEmpty {
                    HStack(spacing: 10) {
                        if shouldShowMore {
                            Button(showRaw ? "Show less" : "Show more") {
                                withAnimation(.easeOut(duration: 0.15)) { showRaw.toggle() }
                            }
                            .buttonStyle(.plain)
                            .font(SettingsDesign.captionFont)
                            .foregroundStyle(SettingsDesign.accentBlue)
                        }

                        if !entry.appName.isEmpty {
                            Text(entry.appName)
                                .font(SettingsDesign.captionFont)
                                .foregroundStyle(.secondary.opacity(0.75))
                        }
                    }
                    .padding(.top, 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // REGION 3: Trailing Actions
            HStack(spacing: 10) {
                Button {
                    copy(entry.cleaned)
                } label: {
                    Group {
                        switch copyState {
                        case .idle:
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.secondary)
                        case .copied:
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.green)
                        case .failed:
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 14))
                                .foregroundStyle(.red)
                        }
                    }
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Copy text to clipboard")

                Button(role: .destructive) {
                    entryToDelete = entry
                    showingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Delete transcription")
            }
            .opacity(isHovered || copyState != .idle ? 1.0 : 0.35)
            .padding(.top, 2)
        }
        .padding(.vertical, SettingsDesign.dictationRowVerticalPadding)
        .padding(.horizontal, 6)
        .wfHoverElevation(cornerRadius: SettingsDesign.smallControlRadius)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Copy") { copy(entry.cleaned) }
            if shouldShowMore {
                Button(showRaw ? "Show Less" : "Show More") { showRaw.toggle() }
            }
            Divider()
            Button("Delete", role: .destructive) {
                entryToDelete = entry
                showingDeleteConfirmation = true
            }
        }
    }

    private var shouldShowMore: Bool {
        if entry.isCommand { return !entry.raw.isEmpty && entry.raw != (entry.commandSummary ?? entry.cleaned) }
        return entry.cleaned.count > 130 || entry.raw != entry.cleaned
    }

    private func copy(_ text: String) {
        copyResetTask?.cancel()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let success = pasteboard.setString(text, forType: .string)
        if success {
            withAnimation(.easeInOut(duration: 0.15)) {
                copyState = .copied
            }
        } else {
            withAnimation(.easeInOut(duration: 0.15)) {
                copyState = .failed
            }
        }
        copyResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                copyState = .idle
            }
        }
    }
}