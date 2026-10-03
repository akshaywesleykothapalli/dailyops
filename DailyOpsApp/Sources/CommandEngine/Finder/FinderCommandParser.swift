import Foundation

/// Parses Finder and file navigation voice commands into structured CommandPlans.
@MainActor
struct FinderCommandParser: CommandParsing {
    func parse(_ transcript: String, context: CommandContext) -> CommandPlan? {
        guard context.isCommandModeEnabled else { return nil }
        let raw = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".?!"))
        guard !raw.isEmpty else { return nil }
        var lower = raw.lowercased()
        if lower.hasSuffix(" please") {
            lower = String(lower.dropLast(" please".count)).trimmingCharacters(in: .whitespaces)
        }

        // 1. Extended Finder operations (create, reveal, trash, rename, duplicate)
        if let createFolderRequest = parseCreateFolderCommand(raw: raw, lower: lower) {
            return CommandPlan(intent: CommandIntent(
                identifier: .finderCreateFolder,
                arguments: .finderCreateFolder(createFolderRequest)
            ))
        }

        if let createFileRequest = parseCreateFileCommand(raw: raw, lower: lower) {
            return CommandPlan(intent: CommandIntent(
                identifier: .finderCreateFile,
                arguments: .finderCreateFile(createFileRequest)
            ))
        }

        if let revealRequest = parseRevealCommand(raw: raw, lower: lower) {
            return CommandPlan(intent: CommandIntent(
                identifier: .finderReveal,
                arguments: .finderReveal(revealRequest)
            ))
        }

        if let trashRequest = parseTrashCommand(raw: raw, lower: lower) {
            return CommandPlan(intent: CommandIntent(
                identifier: .finderTrash,
                arguments: .finderTrash(trashRequest)
            ))
        }

        if let renameRequest = parseRenameCommand(raw: raw, lower: lower) {
            return CommandPlan(intent: CommandIntent(
                identifier: .finderRename,
                arguments: .finderRename(renameRequest)
            ))
        }

        if let duplicateRequest = parseDuplicateCommand(raw: raw, lower: lower) {
            return CommandPlan(intent: CommandIntent(
                identifier: .finderDuplicate,
                arguments: .finderDuplicate(duplicateRequest)
            ))
        }

        // 1. File searches ("find my screenshots", "find files in Downloads", "show files modified today")
        if let searchRequest = parseSearchCommand(lower: lower) {
            return CommandPlan(intent: CommandIntent(
                identifier: .finderFindFiles,
                arguments: .fileSearch(searchRequest)
            ))
        }

        // 2. Standard location targets ("open Downloads", "open Desktop", "open Finder", etc.)
        if let locationTarget = parseLocationCommand(raw: raw, lower: lower) {
            return CommandPlan(intent: CommandIntent(
                identifier: .finderOpenLocation,
                arguments: .finderLocation(locationTarget)
            ))
        }

        return nil
    }

    // MARK: - File Search Parsing

    private func parseSearchCommand(lower: String) -> FileSearchRequest? {
        // Screenshots
        if lower == "find my screenshots"
            || lower == "find screenshots"
            || lower == "show my screenshots"
            || lower == "show screenshots"
            || lower == "my screenshots" {
            return FileSearchRequest(scope: .desktop, filter: .screenshots)
        }

        // PDFs in specific scopes
        if lower == "find my pdfs"
            || lower == "find pdfs"
            || lower == "show my pdfs"
            || lower == "show pdfs"
            || lower == "my pdfs"
            || lower == "find pdf files"
            || lower == "show pdf files"
            || lower == "find pdf documents"
            || lower == "show pdf documents" {
            return FileSearchRequest(scope: .downloads, filter: .pdfs)
        }

        // Scoped PDF searches: "find PDF files in Documents", "search PDFs in Downloads", etc.
        if let scopedPDFRequest = parseScopedPDFSearch(lower: lower) {
            return scopedPDFRequest
        }

        // Modified today
        if lower == "show files modified today"
            || lower == "find files modified today"
            || lower == "files modified today"
            || lower == "show files created today"
            || lower == "find files created today" {
            return FileSearchRequest(scope: .downloads, filter: .modifiedToday)
        }

        // Modified yesterday
        if lower == "show files modified yesterday"
            || lower == "find files modified yesterday"
            || lower == "files modified yesterday" {
            return FileSearchRequest(scope: .downloads, filter: .modifiedYesterday)
        }

        // Modified this week
        if lower == "show files modified this week"
            || lower == "find files modified this week"
            || lower == "files modified this week" {
            return FileSearchRequest(scope: .downloads, filter: .modifiedThisWeek)
        }

        // Files in specific folders
        if lower == "find files in downloads"
            || lower == "show files in downloads"
            || lower == "list files in downloads"
            || lower == "files in downloads" {
            return FileSearchRequest(scope: .downloads, filter: .all)
        }

        if lower == "find files in documents"
            || lower == "show files in documents"
            || lower == "list files in documents"
            || lower == "files in documents" {
            return FileSearchRequest(scope: .documents, filter: .all)
        }

        if lower == "find files on desktop"
            || lower == "find files in desktop"
            || lower == "show files on desktop"
            || lower == "files on desktop" {
            return FileSearchRequest(scope: .desktop, filter: .all)
        }

        if lower == "find files in pictures"
            || lower == "show files in pictures"
            || lower == "list files in pictures"
            || lower == "files in pictures" {
            return FileSearchRequest(scope: .pictures, filter: .all)
        }

        return nil
    }

    // MARK: - Scoped PDF Search Parsing

    private func parseScopedPDFSearch(lower: String) -> FileSearchRequest? {
        // "find PDF files in Documents", "find PDFs in Documents", "search for PDF files in Documents"
        // "find PDFs in my Documents", "search PDFs in Downloads", "find PDF files in Desktop"
        // "find PDF files in Pictures"

        let pdfPatterns: [(prefixes: [String], scope: FileSearchScope)] = [
            (["find pdf files in ", "find pdfs in ", "search for pdf files in ", "search pdfs in "], .documents),
            (["find pdf files in my ", "find pdfs in my "], .documents),
            (["find pdf files in ", "find pdfs in ", "search pdfs in "], .downloads),
            (["find pdf files in ", "find pdfs in ", "search pdfs in "], .desktop),
            (["find pdf files in ", "find pdfs in ", "search pdfs in "], .pictures),
        ]

        for pattern in pdfPatterns {
            for prefix in pattern.prefixes {
                if lower.hasPrefix(prefix) {
                    let remainder = String(lower.dropFirst(prefix.count))
                    // Match the scope name at the start of the remainder
                    let scopeKeywords: [(keyword: String, scope: FileSearchScope)] = [
                        ("documents", .documents),
                        ("downloads", .downloads),
                        ("desktop", .desktop),
                        ("pictures", .pictures),
                    ]
                    for (keyword, scope) in scopeKeywords {
                        if remainder.hasPrefix(keyword) {
                            return FileSearchRequest(scope: scope, filter: .pdfs)
                        }
                    }
                }
            }
        }

        return nil
    }

    // MARK: - Location Navigation Parsing

    private func parseLocationCommand(raw: String, lower: String) -> FinderLocationTarget? {
        // Standard system folders
        let downloadsPhrases = [
            "open downloads", "show downloads", "go to downloads", "view downloads",
            "open downloads folder", "show downloads folder", "go to downloads folder",
            "open my downloads", "open my downloads folder", "show my downloads",
            "open the downloads", "open the downloads folder", "show the downloads",
            "show the downloads folder"
        ]
        if downloadsPhrases.contains(lower) {
            return FinderLocationTarget(location: .downloads)
        }

        let desktopPhrases = [
            "open desktop", "show desktop", "go to desktop", "view desktop",
            "open desktop folder", "show desktop folder", "go to desktop folder",
            "open my desktop", "open my desktop folder", "show my desktop",
            "open the desktop", "open the desktop folder", "show the desktop",
            "show the desktop folder"
        ]
        if desktopPhrases.contains(lower) {
            return FinderLocationTarget(location: .desktop)
        }

        let documentsPhrases = [
            "open documents", "show documents", "go to documents", "view documents",
            "open documents folder", "show documents folder", "go to documents folder",
            "open my documents", "open my documents folder", "show my documents",
            "open the documents", "open the documents folder", "show the documents",
            "show the documents folder"
        ]
        if documentsPhrases.contains(lower) {
            return FinderLocationTarget(location: .documents)
        }

        let applicationsPhrases = [
            "open applications", "show applications", "go to applications", "view applications",
            "open applications folder", "show applications folder", "go to applications folder",
            "open my applications", "open my applications folder", "show my applications",
            "open the applications", "open the applications folder", "show the applications",
            "show the applications folder"
        ]
        if applicationsPhrases.contains(lower) {
            return FinderLocationTarget(location: .applications)
        }

        let homePhrases = [
            "open home", "open home folder", "show home folder", "go to home folder",
            "open my home folder", "open user folder", "open my user folder",
            "show home", "show my home", "open the home folder", "show the home folder"
        ]
        if homePhrases.contains(lower) {
            return FinderLocationTarget(location: .home)
        }

        let picturesPhrases = [
            "open pictures", "show pictures", "go to pictures", "view pictures",
            "open pictures folder", "show pictures folder", "go to pictures folder",
            "open my pictures", "open my pictures folder", "show my pictures",
            "open the pictures", "open the pictures folder", "show the pictures",
            "show the pictures folder"
        ]
        if picturesPhrases.contains(lower) {
            return FinderLocationTarget(location: .pictures)
        }

        let finderPhrases = [
            "open finder", "launch finder", "show finder", "start finder"
        ]
        if finderPhrases.contains(lower) {
            return FinderLocationTarget(location: .finder)
        }

        // Custom folder opening: "open folder <name>" or "show folder <name>"
        let explicitFolderPrefixes = [
            "open folder ",
            "show folder "
        ]
        for prefix in explicitFolderPrefixes {
            if lower.hasPrefix(prefix) {
                var folderName = String(raw.dropFirst(prefix.count))
                if folderName.lowercased().hasSuffix(" folder") {
                    folderName = String(folderName.dropLast(" folder".count))
                }
                folderName = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !folderName.isEmpty {
                    return FinderLocationTarget(location: .custom, customName: folderName)
                }
            }
        }

        // Prefixes like "open my <name> folder" or "open the <name> folder" MUST explicitly end with " folder"
        // so they do not hijack non-folder commands (e.g. "open my browser", "open the browser") or dictation.
        let qualifiedFolderPrefixes = [
            "open my ",
            "open the ",
            "show my ",
            "show the "
        ]
        for prefix in qualifiedFolderPrefixes {
            if lower.hasPrefix(prefix) && (lower.hasSuffix(" folder") || lower.hasSuffix(" directory")) {
                var folderName = String(raw.dropFirst(prefix.count))
                if folderName.lowercased().hasSuffix(" directory") {
                    folderName = String(folderName.dropLast(" directory".count))
                } else if folderName.lowercased().hasSuffix(" folder") {
                    folderName = String(folderName.dropLast(" folder".count))
                }
                folderName = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !folderName.isEmpty {
                    return FinderLocationTarget(location: .custom, customName: folderName)
                }
            }
        }

return nil
    }
}

    // MARK: - Extended Finder Operations Parsing

    private func parseCreateFolderCommand(raw: String, lower: String) -> FinderCreateFolderRequest? {
        let createFolderPrefixes = [
            "create a folder called ",
            "create a folder named ",
            "create folder called ",
            "create folder named ",
            "make a folder called ",
            "make a folder named ",
            "make folder called ",
            "make folder named "
        ]

        for prefix in createFolderPrefixes {
            if lower.hasPrefix(prefix) {
                let remaining = String(raw.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if let range = remaining.lowercased().range(of: " in ") {
                    let folderName = String(remaining[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let parentPath = String(remaining[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !folderName.isEmpty {
                        return FinderCreateFolderRequest(folderName: folderName, parentPath: parentPath.isEmpty ? nil : parentPath)
                    }
                } else if let range = remaining.lowercased().range(of: " on ") {
                    let folderName = String(remaining[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let parentPath = String(remaining[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !folderName.isEmpty {
                        return FinderCreateFolderRequest(folderName: folderName, parentPath: parentPath.isEmpty ? nil : parentPath)
                    }
                } else if !remaining.isEmpty {
                    return FinderCreateFolderRequest(folderName: remaining, parentPath: nil)
                }
            }
        }
        return nil
    }

    private func parseCreateFileCommand(raw: String, lower: String) -> FinderCreateFileRequest? {
        let createFilePrefixes = [
            "create a file called ",
            "create a file named ",
            "create file called ",
            "create file named ",
            "make a file called ",
            "make a file named ",
            "make file called ",
            "make file named "
        ]

        for prefix in createFilePrefixes {
            if lower.hasPrefix(prefix) {
                let remaining = String(raw.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if let range = remaining.lowercased().range(of: " in ") {
                    let fileName = String(remaining[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let parentPath = String(remaining[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !fileName.isEmpty {
                        return FinderCreateFileRequest(fileName: fileName, parentPath: parentPath.isEmpty ? nil : parentPath)
                    }
                } else if let range = remaining.lowercased().range(of: " on ") {
                    let fileName = String(remaining[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let parentPath = String(remaining[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !fileName.isEmpty {
                        return FinderCreateFileRequest(fileName: fileName, parentPath: parentPath.isEmpty ? nil : parentPath)
                    }
                } else if !remaining.isEmpty {
                    return FinderCreateFileRequest(fileName: remaining, parentPath: nil)
                }
            }
        }
        return nil
    }

    private func parseRevealCommand(raw: String, lower: String) -> FinderRevealRequest? {
        let revealPrefixes = [
            "show in finder ",
            "reveal in finder ",
            "reveal "
        ]

        for prefix in revealPrefixes {
            if lower.hasPrefix(prefix) {
                let path = String(raw.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !path.isEmpty {
                    return FinderRevealRequest(path: path)
                }
            }
        }
        return nil
    }

    private func parseTrashCommand(raw: String, lower: String) -> FinderTrashRequest? {
        let trashPrefixes = [
            "move to trash ",
            "trash ",
            "move to the trash "
        ]

        for prefix in trashPrefixes {
            if lower.hasPrefix(prefix) {
                let path = String(raw.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !path.isEmpty {
                    return FinderTrashRequest(path: path)
                }
            }
        }
        return nil
    }

    private func parseRenameCommand(raw: String, lower: String) -> FinderRenameRequest? {
        let renamePrefixes = [
            "rename ",
            "rename to "
        ]

        for prefix in renamePrefixes {
            if lower.hasPrefix(prefix) {
                let remaining = String(raw.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if let range = remaining.lowercased().range(of: " to ") {
                    let oldPath = String(remaining[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let newName = String(remaining[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !oldPath.isEmpty && !newName.isEmpty {
                        return FinderRenameRequest(oldPath: oldPath, newName: newName)
                    }
                }
            }
        }
        return nil
    }

    private func parseDuplicateCommand(raw: String, lower: String) -> FinderDuplicateRequest? {
        let duplicatePrefixes = [
            "duplicate ",
            "copy "
        ]

        for prefix in duplicatePrefixes {
            if lower.hasPrefix(prefix) {
                let path = String(raw.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !path.isEmpty {
                    return FinderDuplicateRequest(path: path)
                }
            }
        }
        return nil
    }
