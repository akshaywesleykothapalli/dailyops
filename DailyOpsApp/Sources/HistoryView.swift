import SwiftData
import SwiftUI

struct HistoryView: View {
    @Query(sort: \DictationEntry.date, order: .reverse) private var entries: [DictationEntry]
    @Environment(\.modelContext) private var context
    @Binding var search: String
    @State private var deleteErrorMessage: String?
    @State private var entryToDelete: DictationEntry?
    @State private var showingDeleteConfirmation = false

    var body: some View {
        let sections = HistoryGrouping.sections(from: entries, matching: search)

        HistoryList(sections: sections, entryToDelete: $entryToDelete, showingDeleteConfirmation: $showingDeleteConfirmation) { entry in
            withAnimation(.easeOut(duration: 0.18)) {
                context.delete(entry)
            }
            do {
                try context.save()
            } catch {
                log.error("Could not delete history entry: \(error.localizedDescription)")
                deleteErrorMessage = "Could not delete: \(error.localizedDescription)"
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No Dictations Yet",
                    systemImage: "waveform",
                    description: Text("Hold your chosen push-to-talk key anywhere to dictate. Transcriptions will appear here.")
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
                    log.error("Could not delete history entry: \(error.localizedDescription)")
                    deleteErrorMessage = "Could not delete: \(error.localizedDescription)"
                }
            }
        } message: { _ in
            Text("This entry will be permanently removed from your local history.")
        }
        .tint(SettingsDesign.accentBlue)
    }
}

/// The scrolling history list.
private struct HistoryList: View {
    let sections: [HistorySection]
    @Binding var entryToDelete: DictationEntry?
    @Binding var showingDeleteConfirmation: Bool
    let onDelete: (DictationEntry) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(sections) { section in
                    Section {
                        VStack(spacing: 0) {
                            ForEach(section.rows) { row in
                                EntryRow(
                                    entry: row.entry,
                                    time: row.time,
                                    entryToDelete: $entryToDelete,
                                    showingDeleteConfirmation: $showingDeleteConfirmation
                                )
                            }
                        }
                        .padding(.horizontal, SettingsDesign.contentHorizontalMargin)
                    } header: {
                        HistorySectionHeader(title: section.title, count: section.rows.count)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .defaultScrollAnchor(.top)
    }
}

/// Pinned section header matching native macOS list views.
private struct HistorySectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)

            Text("\(count)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Color.primary.opacity(0.05), in: Capsule())

            Spacer()
        }
        .padding(.horizontal, SettingsDesign.contentHorizontalMargin)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Rectangle()
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(alignment: .bottom) {
                    Divider().opacity(0.4)
                }
        )
        .accessibilityAddTraits(.isHeader)
    }
}

private enum CopyFeedbackState: Equatable {
    case idle
    case copied
    case failed
}

private struct EntryRow: View {
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
            // Timestamp
            Text(time)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
                .padding(.top, 2)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                if entry.isCommand {
                    HStack(spacing: 5) {
                        Image(systemName: "command")
                            .font(.system(size: 9, weight: .bold))
                        Text("COMMAND")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.5)
                    }
                    .foregroundStyle(SettingsDesign.accentBlue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(SettingsDesign.accentBlue.opacity(0.10), in: RoundedRectangle(cornerRadius: 4))
                }

                Text(showRaw ? entry.raw : (entry.isCommand ? (entry.commandSummary ?? entry.cleaned) : entry.cleaned))
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(Color.primary)
                    .lineLimit(showRaw ? nil : 3)
                    .lineSpacing(2)
                    .textSelection(.enabled)

                HStack(spacing: 8) {
                    if shouldShowMore {
                        Button(showRaw ? "Show less" : "Show more") {
                            withAnimation(.easeOut(duration: 0.15)) { showRaw.toggle() }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(SettingsDesign.accentBlue)
                    }

                    if !entry.appName.isEmpty {
                        Text(entry.appName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer(minLength: 16)

            // Trailing actions (Copy, Delete)
            HStack(spacing: 6) {
                Button {
                    copy(entry.cleaned)
                } label: {
                    HStack(spacing: 3) {
                        switch copyState {
                        case .idle:
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 12))
                        case .copied:
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.green)
                            Text("Copied")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.green)
                        case .failed:
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.red)
                        }
                    }
                    .frame(height: 22)
                    .padding(.horizontal, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(copyState == .copied ? .green : .secondary)
                .help("Copy text")

                Button(role: .destructive) {
                    entryToDelete = entry
                    showingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Delete transcription")
            }
            .opacity(isHovered || copyState != .idle ? 1.0 : 0.6)
            .padding(.top, 2)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.primary.opacity(0.03) : Color.clear)
        )
        .overlay(alignment: .bottom) {
            Divider()
                .opacity(0.3)
                .padding(.leading, 74)
        }
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
