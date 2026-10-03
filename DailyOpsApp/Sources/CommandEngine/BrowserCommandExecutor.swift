import AppKit
import Foundation

/// Protocol governing URL opening and browser launching in the user's default browser.
@MainActor
protocol BrowserControlling {
    func open(_ url: URL) throws
    func openDefaultBrowser() throws -> String
    func openPrivateWindow() throws -> String
}

/// Native implementation of BrowserControlling using AppKit NSWorkspace and LaunchServices.
@MainActor
struct SystemBrowserControl: BrowserControlling {
    func open(_ url: URL) throws {
        guard NSWorkspace.shared.open(url) else {
            throw CommandExecutionError.operationFailed("Failed to open \(url.absoluteString)")
        }
    }

    /// Resolves the actual default browser configured in macOS LaunchServices.
    func defaultBrowserApplicationURL() -> URL? {
        guard let probe = URL(string: "https://") else { return nil }
        return NSWorkspace.shared.urlForApplication(toOpen: probe)
    }

    func openDefaultBrowser() throws -> String {
        guard let appURL = defaultBrowserApplicationURL() else {
            throw CommandExecutionError.operationFailed("Could not resolve default browser.")
        }
        let appName = (try? appURL.resourceValues(forKeys: [.localizedNameKey]))?.localizedName
            ?? appURL.deletingPathExtension().lastPathComponent
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: config, completionHandler: nil)
        return "Opened \(appName)"
    }

    func openPrivateWindow() throws -> String {
        guard let appURL = defaultBrowserApplicationURL() else {
            throw CommandExecutionError.operationFailed("Could not resolve default browser.")
        }
        let appName = (try? appURL.resourceValues(forKeys: [.localizedNameKey]))?.localizedName
            ?? appURL.deletingPathExtension().lastPathComponent
        let bundleId = Bundle(url: appURL)?.bundleIdentifier?.lowercased() ?? ""

        // Only use supported, public, native CLI flags for browsers that expose them.
        // Chrome, Brave: --incognito
        // Edge: --inprivate
        // Firefox: --private-window
        let privateFlag: String?
        if bundleId.contains("chrome") || bundleId.contains("brave") {
            privateFlag = "--incognito"
        } else if bundleId.contains("edgemac") || bundleId.contains("edge") {
            privateFlag = "--inprivate"
        } else if bundleId.contains("firefox") {
            privateFlag = "--private-window"
        } else if bundleId.contains("safari") {
            // Safari does not expose a supported public native CLI mechanism or URL scheme
            // for opening private browsing windows without AppleScript / osascript / simulated keystrokes.
            // Per product requirement: fail honestly instead of opening a normal window and pretending it is private.
            throw CommandExecutionError.operationFailed("Safari does not support launching private browsing directly.")
        } else {
            throw CommandExecutionError.operationFailed("\(appName) does not support launching private browsing directly.")
        }

        if let flag = privateFlag {
            let config = NSWorkspace.OpenConfiguration()
            config.arguments = [flag]
            config.activates = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: config, completionHandler: nil)
            return "Opened private window in \(appName)"
        } else {
            throw CommandExecutionError.operationFailed("\(appName) does not support launching private browsing directly.")
        }
    }
}

/// Normalizes, validates, and cleans web URL inputs.
enum URLNormalizer {
    /// Supported domain suffixes / TLDs for bare-domain detection.
    private static let commonTLDs: Set<String> = [
        "com", "org", "net", "io", "dev", "app", "ai", "co", "uk", "edu", "gov",
        "ca", "de", "fr", "jp", "au", "in", "me", "info", "xyz", "tv", "gg"
    ]

    /// Known website shortcuts mapped directly to their homepages.
    private static let knownWebsites: [String: String] = [
        "youtube": "https://www.youtube.com",
        "youtube.com": "https://www.youtube.com",
        "google": "https://www.google.com",
        "google.com": "https://www.google.com",
        "github": "https://github.com",
        "github.com": "https://github.com",
        "reddit": "https://www.reddit.com",
        "reddit.com": "https://www.reddit.com",
        "twitter": "https://x.com",
        "x": "https://x.com",
        "wikipedia": "https://www.wikipedia.org",
        "wikipedia.org": "https://www.wikipedia.org"
    ]

    /// Attempts to parse and normalize user text into a valid HTTP/HTTPS URL.
    /// Rejects non-HTTP(S) schemes (such as file:, javascript:, data:) to prevent arbitrary command execution.
    static func normalize(_ rawInput: String) -> URL? {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()

        // 1. Check known website shortcuts
        if let direct = knownWebsites[lower], let url = URL(string: direct) {
            return url
        }

        // 2. If it has an explicit scheme, verify it is strictly http or https
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  let host = url.host, !host.isEmpty else {
                return nil
            }
            return url
        }

        // 3. Reject any other explicit scheme (e.g. "javascript:", "file:", "data:")
        if lower.contains(":") {
            return nil
        }

        // 4. Handle "www." prefix or domain with valid TLD
        let candidateString: String
        if lower.hasPrefix("www.") {
            candidateString = "https://" + trimmed
        } else {
            let hostPart = trimmed.split(separator: "/").first.map(String.init) ?? trimmed
            let parts = hostPart.split(separator: ".")
            guard parts.count >= 2, let tld = parts.last?.lowercased(), commonTLDs.contains(tld) else {
                return nil
            }
            candidateString = "https://" + trimmed
        }

        guard let url = URL(string: candidateString),
              let host = url.host, !host.isEmpty, host.contains(".") else {
            return nil
        }
        return url
    }
}

/// Constructs search URLs for supported search providers.
enum WebSearchBuilder {
    static func searchURL(for request: SearchRequest) -> URL? {
        let query = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        switch request.provider {
        case .google:
            components.host = "www.google.com"
            components.path = "/search"
            components.queryItems = [URLQueryItem(name: "q", value: query)]
        case .youtube:
            components.host = "www.youtube.com"
            components.path = "/results"
            components.queryItems = [URLQueryItem(name: "search_query", value: query)]
        }

        if let encoded = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B") {
            components.percentEncodedQuery = encoded
        }

        return components.url
    }
}

/// Executes browser URL and web search commands.
@MainActor
struct BrowserCommandExecutor: CommandExecuting {
    private let control: BrowserControlling

    let supportedIdentifiers: Set<CommandIdentifier> = [
        .browserOpenURL,
        .browserSearch,
        .browserOpenDefault,
        .browserOpenPrivate
    ]

    init(control: BrowserControlling) {
        self.control = control
    }

    func execute(_ intent: CommandIntent, context: CommandContext) throws -> String {
        switch intent.identifier {
        case .browserOpenURL:
            let url = try urlArgument(from: intent)
            try control.open(url)
            let host = url.host ?? url.absoluteString
            return "Opened \(host)"

        case .browserSearch:
            let request = try searchArgument(from: intent)
            guard let url = WebSearchBuilder.searchURL(for: request) else {
                throw CommandExecutionError.operationFailed("Could not build search query.")
            }
            try control.open(url)
            return "Searched \(request.provider.displayName) for '\(request.query)'"

        case .browserOpenDefault:
            return try control.openDefaultBrowser()

        case .browserOpenPrivate:
            return try control.openPrivateWindow()

        default:
            throw CommandExecutionError.unsupported(intent.identifier)
        }
    }
}
