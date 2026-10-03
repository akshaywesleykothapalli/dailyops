import Foundation

/// Headless pipeline check: `DailyOps.app/Contents/MacOS/DailyOps --selftest audio.wav`
/// transcribes the file with Parakeet, runs deterministic cleanup, prints
/// both, and exits. Exercises the real model stack without mic or permissions.
@MainActor
enum SelfTest {
    static func runIfRequested() -> Bool {
        // `--record-test`: capture the mic for a few seconds and report RMS.
        // Used to observe which system recording indicator the capture path
        // triggers, without needing a hotkey press.
        if CommandLine.arguments.contains("--record-test") {
            Task {
                let recorder = AudioRecorder()
                // Deliberately no permission request here: isolates which
                // API triggers the system recording indicator.
                do {
                    try recorder.start()
                    try? await Task.sleep(for: .seconds(6))
                    let samples = recorder.stop()
                    let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(max(samples.count, 1)))
                    print("RECORD_TEST: \(samples.count) samples, rms \(rms)")
                    exit(0)
                } catch {
                    print("RECORD_TEST FAILED: \(error.localizedDescription)")
                    exit(1)
                }
            }
            return true
        }

        guard let index = CommandLine.arguments.firstIndex(of: "--selftest"),
              CommandLine.arguments.count > index + 1 else { return false }
        let url = URL(fileURLWithPath: CommandLine.arguments[index + 1])

        Task {
            do {
                CleanupService.prewarm()
                let clock = ContinuousClock()
                let transcriber = TranscriptionService()

                var start = clock.now
                let raw = try await transcriber.transcribeFile(url)
                print("RAW (\(clock.now - start)): \(raw)")

                print("CLEANUP_AVAILABLE: \(CleanupService.isAvailable)")
                print("LOCALE: \(Locale.current.identifier) preferred=\(Bundle.main.preferredLocalizations)")
                start = clock.now
                let cleaned = await CleanupService.clean(raw, vocabulary: [AppBrand.displayName])
                print("CLEANED (\(clock.now - start)): \(cleaned)")

                start = clock.now
                let formalCleaned = await CleanupService.clean(raw, vocabulary: [AppBrand.displayName], formal: true)
                print("FORMAL (\(clock.now - start)): \(formalCleaned)")

                // Verify Command Mode and Application Discovery
                let discovery = ApplicationDiscovery.shared
                discovery.scanApplications()
                let calcFound = discovery.findApplication(named: "calculator") != nil
                // Parsing only; the plan is printed rather than executed, so the
                // self test never launches an application.
                let parser = DeterministicCommandParser(applications: SystemApplicationResolver(discovery: discovery))
                let context = CommandContext(
                    frontmostApplicationName: "",
                    timestamp: Date(),
                    isCommandModeEnabled: true
                )
                let parsedPlan = parser.parse("open calculator", context: context)
                let parsedIntent = parsedPlan?.steps.first?.intent.identifier.rawValue
                print("APP_DISCOVERY_TEST: calculator found=\(calcFound) intent=\(String(describing: parsedIntent))")

                exit(raw.isEmpty ? 1 : 0)
            } catch {
                print("SELFTEST FAILED: \(error.localizedDescription)")
                exit(1)
            }
        }
        return true
    }
}
