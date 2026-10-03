import AppKit

/// Adapts the existing installed-application index to the engine's resolver
/// protocol. The index itself is unchanged; this only translates its results
/// into `ApplicationReference` values and holds onto the `NSRunningApplication`
/// that a quit or hide will act on.
@MainActor
final class SystemApplicationResolver: ApplicationResolving {
    private let discovery: ApplicationDiscovery
    private let registry: ApplicationRegistry
    /// Running processes matched during parsing, keyed by the reference shown
    /// to the user. Cleared each lookup round so a stale process is never
    /// carried into a later command.
    private var matchedProcesses: [String: NSRunningApplication] = [:]

    init(
        discovery: ApplicationDiscovery = .shared,
        registry: ApplicationRegistry = ApplicationRegistry()
    ) {
        self.discovery = discovery
        self.registry = registry
    }

    func installedApplication(named query: String) -> ApplicationReference? {
        if let known = registry.resolve(named: query) {
            return known
        }
        guard let found = discovery.findApplication(named: query) else { return nil }
        return ApplicationReference(displayName: found.name.capitalized, bundleURL: found.url)
    }

    func runningApplication(named query: String) -> ApplicationReference? {
        if let known = registry.findKnownApplication(named: query) {
            if let running = NSWorkspace.shared.runningApplications.first(where: {
                $0.bundleIdentifier == known.bundleIdentifier ||
                $0.localizedName == known.displayName
            }) {
                let reference = ApplicationReference(displayName: known.displayName, bundleURL: running.bundleURL)
                matchedProcesses[known.displayName] = running
                return reference
            }
        }
        guard let app = discovery.findRunningApplication(named: query) else { return nil }
        let name = app.localizedName ?? query.capitalized
        let reference = ApplicationReference(displayName: name, bundleURL: app.bundleURL)
        matchedProcesses[name] = app
        return reference
    }

    /// The process behind a reference produced by `runningApplication(named:)`,
    /// if it is still running.
    func process(for reference: ApplicationReference) -> NSRunningApplication? {
        if let cached = matchedProcesses[reference.displayName], !cached.isTerminated {
            return cached
        }
        return discovery.findRunningApplication(named: reference.displayName)
    }
}
