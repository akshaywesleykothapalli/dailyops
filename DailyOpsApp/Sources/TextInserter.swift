import AppKit

/// Legacy shim forwarding all text insertion calls to the production PasteService.
@MainActor
public enum TextInserter {
    public static func insert(_ text: String) async {
        _ = await PasteService.shared.insert(text)
    }
}
