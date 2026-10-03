import AppKit
import Foundation

/// Summary of a file result found during search.
struct FileSummary: Equatable, Sendable {
    let name: String
    let url: URL
    let modificationDate: Date?
    let fileSize: Int64?
}

/// Abstract interface for Finder and local file navigation operations.
@MainActor
protocol FinderControlling: Sendable {
    func openLocation(_ target: FinderLocationTarget) throws
    func findFiles(_ request: FileSearchRequest) throws -> [FileSummary]
    func createFolder(_ request: FinderCreateFolderRequest) throws
    func createFile(_ request: FinderCreateFileRequest) throws
    func revealItem(_ request: FinderRevealRequest) throws
    func moveToTrash(_ request: FinderTrashRequest) throws
    func renameItem(_ request: FinderRenameRequest) throws
    func duplicateItem(_ request: FinderDuplicateRequest) throws
}

/// Concrete Finder controller using NSWorkspace and FileManager.
@MainActor
final class SystemFinderControl: FinderControlling {
    private let fileManager = FileManager.default

    func openLocation(_ target: FinderLocationTarget) throws {
        let url: URL
        switch target.location {
        case .downloads:
            guard let dir = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
                throw CommandExecutionError.operationFailed("Downloads folder could not be found.")
            }
            url = dir

        case .desktop:
            guard let dir = fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first else {
                throw CommandExecutionError.operationFailed("Desktop folder could not be found.")
            }
            url = dir

        case .documents:
            guard let dir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                throw CommandExecutionError.operationFailed("Documents folder could not be found.")
            }
            url = dir

        case .applications:
            guard let dir = fileManager.urls(for: .applicationDirectory, in: .localDomainMask).first else {
                throw CommandExecutionError.operationFailed("Applications folder could not be found.")
            }
            url = dir

        case .home:
            url = fileManager.homeDirectoryForCurrentUser

        case .finder:
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder") {
                NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
                return
            }
            url = fileManager.homeDirectoryForCurrentUser

        case .pictures:
            guard let dir = fileManager.urls(for: .picturesDirectory, in: .userDomainMask).first else {
                throw CommandExecutionError.operationFailed("Pictures folder could not be found.")
            }
            url = dir

        case .custom:
            guard let customName = target.customName?.trimmingCharacters(in: .whitespacesAndNewlines), !customName.isEmpty else {
                throw CommandExecutionError.operationFailed("No folder name was specified.")
            }
            url = try resolveCustomFolder(named: customName)
        }

        NSWorkspace.shared.open(url)
    }

    func findFiles(_ request: FileSearchRequest) throws -> [FileSummary] {
        let directoryURL: URL
        switch request.scope {
        case .downloads:
            guard let dir = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
                throw CommandExecutionError.operationFailed("Downloads folder could not be found.")
            }
            directoryURL = dir
        case .desktop:
            guard let dir = fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first else {
                throw CommandExecutionError.operationFailed("Desktop folder could not be found.")
            }
            directoryURL = dir
        case .documents:
            guard let dir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                throw CommandExecutionError.operationFailed("Documents folder could not be found.")
            }
            directoryURL = dir
        case .home:
            directoryURL = fileManager.homeDirectoryForCurrentUser
        case .pictures:
            guard let dir = fileManager.urls(for: .picturesDirectory, in: .userDomainMask).first else {
                throw CommandExecutionError.operationFailed("Pictures folder could not be found.")
            }
            directoryURL = dir
        }

        let resourceKeys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey]
        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? startOfToday

        var summaries: [FileSummary] = []
        for fileURL in fileURLs {
            guard let values = try? fileURL.resourceValues(forKeys: resourceKeys) else { continue }
            if values.isDirectory == true { continue }

            let name = fileURL.lastPathComponent
            let modDate = values.contentModificationDate
            let size = values.fileSize.map { Int64($0) }

            switch request.filter {
            case .all:
                summaries.append(FileSummary(name: name, url: fileURL, modificationDate: modDate, fileSize: size))

            case .screenshots:
                let lowerName = name.lowercased()
                if lowerName.hasPrefix("screenshot")
                    || lowerName.hasPrefix("screen shot")
                    || lowerName.contains("screen shot")
                    || lowerName.contains("screenshot") {
                    summaries.append(FileSummary(name: name, url: fileURL, modificationDate: modDate, fileSize: size))
                }

            case .pdfs:
                let lowerName = name.lowercased()
                if lowerName.hasSuffix(".pdf") {
                    summaries.append(FileSummary(name: name, url: fileURL, modificationDate: modDate, fileSize: size))
                }

            case .modifiedToday:
                if let modDate, modDate >= startOfToday {
                    summaries.append(FileSummary(name: name, url: fileURL, modificationDate: modDate, fileSize: size))
                }

            case .modifiedYesterday:
                if let modDate, modDate >= startOfYesterday && modDate < startOfToday {
                    summaries.append(FileSummary(name: name, url: fileURL, modificationDate: modDate, fileSize: size))
                }

            case .modifiedThisWeek:
                if let modDate, modDate >= startOfWeek {
                    summaries.append(FileSummary(name: name, url: fileURL, modificationDate: modDate, fileSize: size))
                }
            }
        }

        // Sort latest first
        summaries.sort { ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast) }
        return summaries
    }

    private func resolveCustomFolder(named folderName: String) throws -> URL {
        let home = fileManager.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(folderName, isDirectory: true),
            home.appendingPathComponent("Desktop", isDirectory: true).appendingPathComponent(folderName, isDirectory: true),
            home.appendingPathComponent("Documents", isDirectory: true).appendingPathComponent(folderName, isDirectory: true),
            home.appendingPathComponent("Downloads", isDirectory: true).appendingPathComponent(folderName, isDirectory: true)
        ]

        for candidate in candidates {
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
                return candidate
            }
        }

        // Case-insensitive fallback in Desktop, Documents, Home
        let searchRoots = [
            home.appendingPathComponent("Desktop", isDirectory: true),
            home.appendingPathComponent("Documents", isDirectory: true),
            home
        ]

        let lowerQuery = folderName.lowercased()
        for root in searchRoots {
            if let children = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
                for child in children {
                    if child.lastPathComponent.lowercased() == lowerQuery {
                        var isDir: ObjCBool = false
                        if fileManager.fileExists(atPath: child.path, isDirectory: &isDir), isDir.boolValue {
                            return child
                        }
                    }
                }
            }
        }

        throw CommandExecutionError.operationFailed("Could not find folder \"\(folderName)\".")
    }

    func createFolder(_ request: FinderCreateFolderRequest) throws {
        let parentURL: URL
        if let parentPath = request.parentPath {
            parentURL = URL(fileURLWithPath: parentPath)
        } else {
            parentURL = fileManager.homeDirectoryForCurrentUser
        }
        let folderURL = parentURL.appendingPathComponent(request.folderName, isDirectory: true)
        if fileManager.fileExists(atPath: folderURL.path) {
            throw CommandExecutionError.operationFailed("Folder \"\(request.folderName)\" already exists at that location.")
        }
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
    }

    func createFile(_ request: FinderCreateFileRequest) throws {
        let parentURL: URL
        if let parentPath = request.parentPath {
            parentURL = URL(fileURLWithPath: parentPath)
        } else {
            parentURL = fileManager.homeDirectoryForCurrentUser
        }
        let fileURL = parentURL.appendingPathComponent(request.fileName)
        if fileManager.fileExists(atPath: fileURL.path) {
            throw CommandExecutionError.operationFailed("File \"\(request.fileName)\" already exists at that location.")
        }
        fileManager.createFile(atPath: fileURL.path, contents: nil, attributes: nil)
    }

    func revealItem(_ request: FinderRevealRequest) throws {
        let url = URL(fileURLWithPath: request.path)
        guard fileManager.fileExists(atPath: url.path) else {
            throw CommandExecutionError.operationFailed("Item at \"\(request.path)\" does not exist.")
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func moveToTrash(_ request: FinderTrashRequest) throws {
        let url = URL(fileURLWithPath: request.path)
        guard fileManager.fileExists(atPath: url.path) else {
            throw CommandExecutionError.operationFailed("Item at \"\(request.path)\" does not exist.")
        }
        try fileManager.trashItem(at: url, resultingItemURL: nil)
    }

    func renameItem(_ request: FinderRenameRequest) throws {
        let oldURL = URL(fileURLWithPath: request.oldPath)
        guard fileManager.fileExists(atPath: oldURL.path) else {
            throw CommandExecutionError.operationFailed("Item at \"\(request.oldPath)\" does not exist.")
        }
        let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(request.newName)
        if fileManager.fileExists(atPath: newURL.path) {
            throw CommandExecutionError.operationFailed("An item named \"\(request.newName)\" already exists at that location.")
        }
        try fileManager.moveItem(at: oldURL, to: newURL)
    }

    func duplicateItem(_ request: FinderDuplicateRequest) throws {
        let sourceURL = URL(fileURLWithPath: request.path)
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw CommandExecutionError.operationFailed("Item at \"\(request.path)\" does not exist.")
        }
        let destinationURL = sourceURL.deletingLastPathComponent().appendingPathComponent("\(sourceURL.deletingPathExtension().lastPathComponent) copy.\(sourceURL.pathExtension)")
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }
}

/// Fake Finder controller for unit testing.
@MainActor
final class FakeFinderControl: FinderControlling {
    var openedTargets: [FinderLocationTarget] = []
    var filesToReturn: [FileSummary] = []
    var shouldFail: Bool = false

    func openLocation(_ target: FinderLocationTarget) throws {
        if shouldFail {
            throw CommandExecutionError.operationFailed("Folder could not be opened.")
        }
        openedTargets.append(target)
    }

    func findFiles(_ request: FileSearchRequest) throws -> [FileSummary] {
        if shouldFail {
            throw CommandExecutionError.operationFailed("File search failed.")
        }
        return filesToReturn
    }

    func createFolder(_ request: FinderCreateFolderRequest) throws {
        if shouldFail {
            throw CommandExecutionError.operationFailed("Folder creation failed.")
        }
    }

    func createFile(_ request: FinderCreateFileRequest) throws {
        if shouldFail {
            throw CommandExecutionError.operationFailed("File creation failed.")
        }
    }

    func revealItem(_ request: FinderRevealRequest) throws {
        if shouldFail {
            throw CommandExecutionError.operationFailed("Reveal failed.")
        }
    }

    func moveToTrash(_ request: FinderTrashRequest) throws {
        if shouldFail {
            throw CommandExecutionError.operationFailed("Move to trash failed.")
        }
    }

    func renameItem(_ request: FinderRenameRequest) throws {
        if shouldFail {
            throw CommandExecutionError.operationFailed("Rename failed.")
        }
    }

    func duplicateItem(_ request: FinderDuplicateRequest) throws {
        if shouldFail {
            throw CommandExecutionError.operationFailed("Duplicate failed.")
        }
    }
}

/// Executes Finder commands.
@MainActor
struct FinderCommandExecutor: CommandExecuting {
    private let control: FinderControlling

    let supportedIdentifiers: Set<CommandIdentifier> = [
        .finderOpenLocation,
        .finderFindFiles,
        .finderCreateFolder,
        .finderCreateFile,
        .finderReveal,
        .finderTrash,
        .finderRename,
        .finderDuplicate
    ]

    init(control: FinderControlling) {
        self.control = control
    }

    func execute(_ intent: CommandIntent, context: CommandContext) throws -> String {
        switch intent.identifier {
        case .finderOpenLocation:
            guard case .finderLocation(let target) = intent.arguments else {
                throw CommandExecutionError.unsupported(intent.identifier)
            }
            try control.openLocation(target)
            return formatLocationSuccess(target)

        case .finderFindFiles:
            guard case .fileSearch(let request) = intent.arguments else {
                throw CommandExecutionError.unsupported(intent.identifier)
            }
            let files = try control.findFiles(request)
            return formatFilesSuccess(request: request, files: files)

        case .finderCreateFolder:
            guard case .finderCreateFolder(let request) = intent.arguments else {
                throw CommandExecutionError.unsupported(intent.identifier)
            }
            try control.createFolder(request)
            return "Created folder \"\(request.folderName)\"\(request.parentPath.map { " in \($0)" } ?? "")."

        case .finderCreateFile:
            guard case .finderCreateFile(let request) = intent.arguments else {
                throw CommandExecutionError.unsupported(intent.identifier)
            }
            try control.createFile(request)
            return "Created file \"\(request.fileName)\"\(request.parentPath.map { " in \($0)" } ?? "")."

        case .finderReveal:
            guard case .finderReveal(let request) = intent.arguments else {
                throw CommandExecutionError.unsupported(intent.identifier)
            }
            try control.revealItem(request)
            return "Revealed \"\(request.path)\" in Finder."

        case .finderTrash:
            guard case .finderTrash(let request) = intent.arguments else {
                throw CommandExecutionError.unsupported(intent.identifier)
            }
            try control.moveToTrash(request)
            return "Moved \"\(request.path)\" to Trash."

        case .finderRename:
            guard case .finderRename(let request) = intent.arguments else {
                throw CommandExecutionError.unsupported(intent.identifier)
            }
            try control.renameItem(request)
            return "Renamed \"\(request.oldPath)\" to \"\(request.newName)\"."

        case .finderDuplicate:
            guard case .finderDuplicate(let request) = intent.arguments else {
                throw CommandExecutionError.unsupported(intent.identifier)
            }
            try control.duplicateItem(request)
            return "Duplicated \"\(request.path)\"."

        default:
            throw CommandExecutionError.unsupported(intent.identifier)
        }
    }

    private func formatLocationSuccess(_ target: FinderLocationTarget) -> String {
        switch target.location {
        case .downloads: return "Opened Downloads"
        case .desktop: return "Opened Desktop"
        case .documents: return "Opened Documents"
        case .applications: return "Opened Applications"
        case .home: return "Opened Home folder"
        case .finder: return "Opened Finder"
        case .pictures: return "Opened Pictures"
        case .custom:
            let name = target.customName ?? "folder"
            return "Opened \(name)"
        }
    }

    private func formatFilesSuccess(request: FileSearchRequest, files: [FileSummary]) -> String {
        switch request.filter {
        case .screenshots:
            if files.isEmpty {
                return "No screenshots found."
            }
            if files.count == 1 {
                return "Found 1 screenshot: \(files[0].name)."
            }
            return "Found \(files.count) screenshots."

        case .pdfs:
            if files.isEmpty {
                return "No PDF files found."
            }
            if files.count == 1 {
                return "Found 1 PDF: \(files[0].name)."
            }
            return "Found \(files.count) PDF files."

        case .modifiedToday:
            if files.isEmpty {
                return "No files modified today."
            }
            let names = files.prefix(3).map(\.name).joined(separator: ", ")
            return "Found \(files.count) files modified today: \(names)."

        case .modifiedYesterday:
            if files.isEmpty {
                return "No files modified yesterday."
            }
            let names = files.prefix(3).map(\.name).joined(separator: ", ")
            return "Found \(files.count) files modified yesterday: \(names)."

        case .modifiedThisWeek:
            if files.isEmpty {
                return "No files modified this week."
            }
            let names = files.prefix(3).map(\.name).joined(separator: ", ")
            return "Found \(files.count) files modified this week: \(names)."

        case .all:
            let scopeName: String
            switch request.scope {
            case .downloads: scopeName = "Downloads"
            case .desktop: scopeName = "Desktop"
            case .documents: scopeName = "Documents"
            case .home: scopeName = "Home"
            case .pictures: scopeName = "Pictures"
            }
            if files.isEmpty {
                return "No files found in \(scopeName)."
            }
            let names = files.prefix(3).map(\.name).joined(separator: ", ")
            return "Found \(files.count) files in \(scopeName): \(names)."
        }
    }
}
