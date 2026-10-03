import SwiftUI

struct DictionaryPane: View {
    @Bindable var controller: DictationController
    @Binding var search: String
    @Binding var showingAddSheet: Bool

    @State private var itemToEdit: EditDictionaryItem?

    struct EditDictionaryItem: Identifiable {
        let originalKey: String
        let isShortcut: Bool
        var key: String
        var expansion: String
        var id: String { originalKey }
    }

    init(
        controller: DictationController,
        search: Binding<String> = .constant(""),
        showingAddSheet: Binding<Bool> = .constant(false)
    ) {
        self.controller = controller
        _search = search
        _showingAddSheet = showingAddSheet
    }

    private var allEntries: [MyDictionaryEntry] {
        var items: [MyDictionaryEntry] = []

        // Custom words
        for word in controller.vocabulary.words {
            items.append(MyDictionaryEntry(
                id: "word_\(word)",
                key: word,
                type: .word,
                isStarred: controller.vocabulary.isStarred(word)
            ))
        }

        // Replacements / shortcuts
        for (shortcut, expansion) in controller.vocabulary.replacements {
            items.append(MyDictionaryEntry(
                id: "replacement_\(shortcut)",
                key: shortcut,
                type: .shortcut(expansion: expansion),
                isStarred: controller.vocabulary.isStarred(shortcut)
            ))
        }

        // Starred items first, then alphabetical
        return items.sorted { lhs, rhs in
            if lhs.isStarred != rhs.isStarred {
                return lhs.isStarred && !rhs.isStarred
            }
            return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
        }
    }

    private var filteredEntries: [MyDictionaryEntry] {
        if search.isEmpty {
            return allEntries
        }
        return allEntries.filter { item in
            if item.key.localizedCaseInsensitiveContains(search) {
                return true
            }
            if case .shortcut(let expansion) = item.type, expansion.localizedCaseInsensitiveContains(search) {
                return true
            }
            return false
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("My Dictionary")
                    .sectionHeaderStyle()
                    .padding(.horizontal, SettingsDesign.contentHorizontalMargin)
                    .padding(.top, 6)

                if filteredEntries.isEmpty {
                    ContentUnavailableView(
                        search.isEmpty ? "No Dictionary Entries" : "No Matches",
                        systemImage: "character.book.closed",
                        description: Text(search.isEmpty ? "Add custom technical terms, names, or shortcut expansions above." : "No terms match \"\(search)\".")
                    )
                    .frame(maxWidth: .infinity, minHeight: 240)
                    .padding(.horizontal, SettingsDesign.contentHorizontalMargin)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(filteredEntries.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 {
                                WFRowDivider(leadingInset: 44)
                            }
                            DictionaryRow(
                                entry: entry,
                                onToggleStar: {
                                    controller.vocabulary.toggleStarred(entry.key)
                                },
                                onEdit: {
                                    switch entry.type {
                                    case .word:
                                        itemToEdit = EditDictionaryItem(
                                            originalKey: entry.key,
                                            isShortcut: false,
                                            key: entry.key,
                                            expansion: ""
                                        )
                                    case .shortcut(let expansion):
                                        itemToEdit = EditDictionaryItem(
                                            originalKey: entry.key,
                                            isShortcut: true,
                                            key: entry.key,
                                            expansion: expansion
                                        )
                                    }
                                },
                                onDelete: {
                                    switch entry.type {
                                    case .word:
                                        controller.vocabulary.remove(entry.key)
                                    case .shortcut:
                                        controller.vocabulary.removeReplacement(spoken: entry.key)
                                    }
                                }
                            )
                        }
                    }
                    .background(SettingsDesign.groupBackground, in: RoundedRectangle(cornerRadius: SettingsDesign.groupCornerRadius))
                    .overlay {
                        RoundedRectangle(cornerRadius: SettingsDesign.groupCornerRadius)
                            .strokeBorder(SettingsDesign.separatorColor, lineWidth: 1)
                    }
                    .padding(.horizontal, SettingsDesign.contentHorizontalMargin)
                }
            }
            .padding(.bottom, 32)
        }
        .background(SettingsDesign.contentBackground)
        .sheet(isPresented: $showingAddSheet) {
            AddDictionaryDialog(
                onAddWord: { word in
                    controller.vocabulary.add(word)
                    showingAddSheet = false
                },
                onAddShortcut: { shortcut, expansion in
                    controller.vocabulary.addReplacement(spoken: shortcut, replacement: expansion)
                    showingAddSheet = false
                },
                onCancel: {
                    showingAddSheet = false
                }
            )
        }
        .sheet(item: $itemToEdit) { item in
            EditDictionaryDialog(
                item: item,
                onSave: { updatedKey, updatedExpansion in
                    if item.isShortcut {
                        controller.vocabulary.removeReplacement(spoken: item.originalKey)
                        controller.vocabulary.addReplacement(spoken: updatedKey, replacement: updatedExpansion)
                    } else {
                        controller.vocabulary.remove(item.originalKey)
                        controller.vocabulary.add(updatedKey)
                    }
                    itemToEdit = nil
                },
                onCancel: {
                    itemToEdit = nil
                }
            )
        }
    }
}

// MARK: - Models & Row View

private struct MyDictionaryEntry: Identifiable {
    enum EntryType {
        case word
        case shortcut(expansion: String)
    }
    let id: String
    let key: String
    let type: EntryType
    let isStarred: Bool
}

private struct DictionaryRow: View {
    let entry: MyDictionaryEntry
    let onToggleStar: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Star / Favorite Button: ~14-15pt
            Button(action: onToggleStar) {
                Image(systemName: entry.isStarred ? "star.fill" : "star")
                    .font(.system(size: 14))
                    .foregroundStyle(entry.isStarred ? Color.orange : Color.secondary.opacity(0.40))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(entry.isStarred ? "Unstar item" : "Star item")

            // Content
            HStack(spacing: 10) {
                Text(entry.key)
                    .font(SettingsDesign.bodyFontMedium)
                    .foregroundStyle(Color.primary)

                switch entry.type {
                case .word:
                    EmptyView()
                case .shortcut(let expansion):
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)

                    Text(expansion)
                        .font(SettingsDesign.bodyFont)
                        .foregroundStyle(SettingsDesign.accentBlue)
                }
            }

            Spacer()

            // Actions (Edit, Delete) - lightweight
            HStack(spacing: 6) {
                Button(action: onEdit) {
                    Text("Edit")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help("Edit entry")

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("Delete entry")
            }
            .opacity(isHovered ? 1.0 : 0.0)
            .animation(.easeOut(duration: 0.12), value: isHovered)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(minHeight: 36)
        .wfHoverElevation(cornerRadius: SettingsDesign.smallControlRadius)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

// MARK: - Add to Dictionary Dialog

private struct AddDictionaryDialog: View {
    enum Concept: String, CaseIterable, Identifiable {
        case word = "Word / Name"
        case shortcut = "Shortcut / Expansion"
        var id: String { rawValue }
    }

    @State private var selectedConcept: Concept = .word
    @State private var word = ""
    @State private var shortcut = ""
    @State private var expansion = ""

    let onAddWord: (String) -> Void
    let onAddShortcut: (String, String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add to Dictionary")
                .font(.system(size: 18, weight: .semibold))

            // Concept Selector
            Picker("", selection: $selectedConcept) {
                ForEach(Concept.allCases) { concept in
                    Text(concept.rawValue).tag(concept)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.regular)

            // Form inputs
            if selectedConcept == .word {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Word / Name")
                        .font(SettingsDesign.captionFontMedium)
                        .foregroundStyle(.secondary)

                    TextField("e.g. Akshay, Kubernetes, DailyOps", text: $word)
                        .textFieldStyle(.roundedBorder)
                        .font(SettingsDesign.bodyFont)
                        .frame(height: 36)
                        .onSubmit(submit)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Shortcut")
                            .font(SettingsDesign.captionFontMedium)
                            .foregroundStyle(.secondary)

                        TextField("e.g. BTW", text: $shortcut)
                            .textFieldStyle(.roundedBorder)
                            .font(SettingsDesign.bodyFont)
                            .frame(height: 36)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Expansion")
                            .font(SettingsDesign.captionFontMedium)
                            .foregroundStyle(.secondary)

                        TextField("e.g. by the way", text: $expansion)
                            .textFieldStyle(.roundedBorder)
                            .font(SettingsDesign.bodyFont)
                            .frame(height: 36)
                            .onSubmit(submit)
                    }
                }
            }

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.regular)

                Button("Add to Dictionary", action: submit)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(isSubmitDisabled)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 6)
        }
        .padding(24)
        .frame(width: 420)
    }

    private var isSubmitDisabled: Bool {
        if selectedConcept == .word {
            return word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } else {
            return shortcut.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                   expansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func submit() {
        if selectedConcept == .word {
            let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            onAddWord(trimmed)
        } else {
            let s = shortcut.trimmingCharacters(in: .whitespacesAndNewlines)
            let e = expansion.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty, !e.isEmpty else { return }
            onAddShortcut(s, e)
        }
    }
}

// MARK: - Edit Dictionary Dialog

private struct EditDictionaryDialog: View {
    let item: DictionaryPane.EditDictionaryItem
    @State private var key: String
    @State private var expansion: String

    let onSave: (String, String) -> Void
    let onCancel: () -> Void

    init(
        item: DictionaryPane.EditDictionaryItem,
        onSave: @escaping (String, String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.item = item
        _key = State(initialValue: item.key)
        _expansion = State(initialValue: item.expansion)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(item.isShortcut ? "Edit Shortcut" : "Edit Word")
                .font(.system(size: 18, weight: .semibold))

            if item.isShortcut {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Shortcut")
                            .font(SettingsDesign.captionFontMedium)
                            .foregroundStyle(.secondary)
                        TextField("Shortcut", text: $key)
                            .textFieldStyle(.roundedBorder)
                            .font(SettingsDesign.bodyFont)
                            .frame(height: 36)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Expansion")
                            .font(SettingsDesign.captionFontMedium)
                            .foregroundStyle(.secondary)
                        TextField("Expansion", text: $expansion)
                            .textFieldStyle(.roundedBorder)
                            .font(SettingsDesign.bodyFont)
                            .frame(height: 36)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Word / Name")
                        .font(SettingsDesign.captionFontMedium)
                        .foregroundStyle(.secondary)
                    TextField("Word", text: $key)
                        .textFieldStyle(.roundedBorder)
                        .font(SettingsDesign.bodyFont)
                        .frame(height: 36)
                }
            }

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.regular)

                Button("Save Changes") {
                    let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
                    let e = expansion.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !k.isEmpty else { return }
                    onSave(k, e)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 6)
        }
        .padding(24)
        .frame(width: 420)
    }
}