import SwiftUI

struct PrivacyPane: View {
    @Bindable var controller: DictationController
    @AppStorage("historyEnabled") private var historyEnabled = true
    @State private var showingDeleteConfirmation = false
    @State private var deletionSuccess = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsDesign.sectionSpacing) {

                // MARK: - History
                WFSection(title: "History") {
                    WFToggleRow(
                        "Store Dictation History",
                        description: "Save transcripts locally so you can review recent speech in the Dictation tab",
                        isOn: $historyEnabled
                    )
                }
                .padding(.horizontal, SettingsDesign.contentHorizontalMargin)

                // MARK: - Processing
                WFSection(title: "Processing") {
                    WFInfoRow(
                        "On-Device Processing",
                        description: "All speech recognition, text cleanup, and dictionary rules run locally",
                        value: "100% Local"
                    )

                    WFRowDivider()

                    WFInfoRow(
                        "Network Privacy",
                        description: "No audio recordings or personal dictations are transmitted to remote servers",
                        value: "Zero Telemetry"
                    )
                }
                .padding(.horizontal, SettingsDesign.contentHorizontalMargin)

                // MARK: - Storage
                WFSection(title: "Storage") {
                    WFInfoRow(
                        "Data Location",
                        description: "Database stored in your user Application Support directory",
                        value: "Local Mac Storage"
                    )

                    WFRowDivider()

                    WFInfoRow(
                        "Cloud Sync",
                        description: "Data is never synced to iCloud or third-party cloud services",
                        value: "Disabled"
                    )
                }
                .padding(.horizontal, SettingsDesign.contentHorizontalMargin)

                // MARK: - Actions (Visually Separate Destructive Action)
                WFSection(title: "Actions") {
                    WFButtonRow(
                        "Delete All History",
                        description: "Permanently erase all stored dictations, transcripts, and command logs",
                        buttonLabel: "Delete All History…",
                        systemImage: "trash",
                        role: .destructive,
                        tint: .red
                    ) {
                        showingDeleteConfirmation = true
                    }
                    .confirmationDialog(
                        "Delete All History?",
                        isPresented: $showingDeleteConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Delete All History", role: .destructive) {
                            controller.history.deleteAll()
                            deletionSuccess = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                deletionSuccess = false
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This permanently purges all past dictations and commands from this Mac. This action cannot be undone.")
                    }

                    if deletionSuccess {
                        WFRowDivider()
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.green)
                            Text("All history records were successfully removed.")
                                .font(SettingsDesign.captionFont)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, SettingsDesign.rowHorizontalPadding)
                        .padding(.vertical, 8)
                    }
                }
                .padding(.horizontal, SettingsDesign.contentHorizontalMargin)

            }
            .padding(.vertical, SettingsDesign.contentVerticalPadding)
        }
        .background(SettingsDesign.contentBackground)
    }
}