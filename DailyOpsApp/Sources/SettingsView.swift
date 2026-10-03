import SwiftUI

struct SettingsView: View {
    @Bindable var controller: DictationController
    let pane: SettingsPane
    @Binding var dictationSearch: String
    @Binding var dictionarySearch: String
    @Binding var showingDictionaryAdd: Bool

    init(
        controller: DictationController,
        pane: SettingsPane = .general,
        dictationSearch: Binding<String> = .constant(""),
        dictionarySearch: Binding<String> = .constant(""),
        showingDictionaryAdd: Binding<Bool> = .constant(false)
    ) {
        self.controller = controller
        self.pane = pane
        _dictationSearch = dictationSearch
        _dictionarySearch = dictionarySearch
        _showingDictionaryAdd = showingDictionaryAdd
    }

    var body: some View {
        switch pane {
        case .workspace:
            WorkspacePane(session: AgentSessionController.shared)
        case .dictation:
            DictationPane(controller: controller, search: $dictationSearch)
        case .insights:
            InsightsPane(controller: controller)
        case .dictionary:
            DictionaryPane(
                controller: controller,
                search: $dictionarySearch,
                showingAddSheet: $showingDictionaryAdd
            )
        case .commandMode:
            CommandModePane()
        case .smartFormatting:
            SmartFormattingPane(controller: controller)
        case .privacy:
            PrivacyPane(controller: controller)
        case .general:
            GeneralPane(controller: controller)
        }
    }
}
