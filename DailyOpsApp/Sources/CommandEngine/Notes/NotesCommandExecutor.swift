import AppKit
import Foundation

/// Summary of a note for display to the user.
struct NoteSummary: Equatable, Sendable {
    let title: String
    let creationDate: Date?
}

/// Abstract interface for Notes operations.
@MainActor
protocol NotesControlling: Sendable {
    func openNotes() throws
    func createNote(_ request: NoteRequest) throws
    func findNotes(_ request: NoteFindRequest) throws -> [NoteSummary]
    func openNote(_ request: NoteOpenRequest) throws -> Bool
}

/// Concrete Notes controller using AppKit NSWorkspace and NSSharingExtension.
@MainActor
final class SystemNotesControl: NotesControlling {
    func openNotes() throws {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Notes") {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        } else if let url = URL(string: "notes:") {
            NSWorkspace.shared.open(url)
        } else {
            throw CommandExecutionError.operationFailed("Notes application could not be opened.")
        }
    }

    func createNote(_ request: NoteRequest) throws {
        var content = request.title
        if let body = request.body, !body.isEmpty {
            content += "\n\n" + body
        }

        let serviceName = NSSharingService.Name("com.apple.Notes.SharingExtension")
        if let service = NSSharingService(named: serviceName), service.canPerform(withItems: [content]) {
            service.perform(withItems: [content])
            return
        }

        // Fallback: open Notes application
        try openNotes()
    }

    func findNotes(_ request: NoteFindRequest) throws -> [NoteSummary] {
        // macOS Notes does not provide a public API for searching notes.
        // We cannot reliably find notes by topic through public APIs.
        throw CommandExecutionError.operationFailed("Note search isn't available through the public macOS API.")
    }

    func openNote(_ request: NoteOpenRequest) throws -> Bool {
        // macOS Notes does not provide a public API for opening a specific note by topic.
        // We can only open the Notes app.
        try openNotes()
        return false
    }
}

/// Fake Notes controller for unit testing.
@MainActor
final class FakeNotesControl: NotesControlling {
    var opened: Bool = false
    var createdNotes: [NoteRequest] = []
    var foundNotes: [NoteSummary] = []
    var openedNotes: [NoteOpenRequest] = []
    var shouldFail: Bool = false

    func openNotes() throws {
        if shouldFail {
            throw CommandExecutionError.operationFailed("Notes application could not be opened.")
        }
        opened = true
    }

    func createNote(_ request: NoteRequest) throws {
        if shouldFail {
            throw CommandExecutionError.operationFailed("Note creation failed.")
        }
        createdNotes.append(request)
    }

    func findNotes(_ request: NoteFindRequest) throws -> [NoteSummary] {
        if shouldFail {
            throw CommandExecutionError.operationFailed("Note search failed.")
        }
        return foundNotes
    }

    func openNote(_ request: NoteOpenRequest) throws -> Bool {
        if shouldFail {
            throw CommandExecutionError.operationFailed("Opening note failed.")
        }
        openedNotes.append(request)
        return false
    }
}

/// Executes Notes commands.
@MainActor
struct NotesCommandExecutor: CommandExecuting {
    private let control: NotesControlling

    let supportedIdentifiers: Set<CommandIdentifier> = [
        .notesOpen,
        .notesCreate,
        .notesFind,
        .notesOpenNote
    ]

    init(control: NotesControlling) {
        self.control = control
    }

    func execute(_ intent: CommandIntent, context: CommandContext) throws -> String {
        switch intent.identifier {
        case .notesOpen:
            try control.openNotes()
            return "Opened Notes"

        case .notesCreate:
            guard case .note(let request) = intent.arguments else {
                throw CommandExecutionError.unsupported(intent.identifier)
            }
            try control.createNote(request)
            return "Note requested — check Notes to confirm."

        case .notesFind:
            guard case .noteFind(let request) = intent.arguments else {
                throw CommandExecutionError.unsupported(intent.identifier)
            }
            let notes = try control.findNotes(request)
            if notes.isEmpty {
                return "No notes found matching \"\(request.query)\". Note search isn't available through the public macOS API."
            }
            let titles = notes.prefix(3).map(\.title).joined(separator: ", ")
            return "Found \(notes.count) notes: \(titles)."

        case .notesOpenNote:
            guard case .noteOpen(let request) = intent.arguments else {
                throw CommandExecutionError.unsupported(intent.identifier)
            }
            let _ = try control.openNote(request)
            return "Opened Notes — look for \"\(request.query)\" in your notes. Opening a specific note by topic isn't available through the public macOS API."

        default:
            throw CommandExecutionError.unsupported(intent.identifier)
        }
    }
}
