import Accelerate
import AppKit
@preconcurrency import AVFoundation
import Foundation
import Observation
import os

/// Transfers a value the compiler can't prove Sendable across a task hop.
/// Used for tap AVAudioPCMBuffers, which are standalone per-callback
/// instances and safe to hand to the streaming transcriber.
struct UncheckedSendable<T>: @unchecked Sendable {
    let value: T
}

let log = Logger(subsystem: AppBrand.bundleIdentifier, category: "dictation")

enum DictationState: Equatable, Sendable {
    case idle
    case recording
    case transcribing
    case processing
    case inserting
    case cleaning
    case polishing(String)
    case done
    case error(String)
    case confirming(ConfirmationRequest)
}

/// Orchestrates the dictation pipeline: hotkey → record → transcribe → clean → insert.
/// Every service it drives is a dumb unit; all sequencing decisions live here.
@MainActor
@Observable
final class DictationController {
    static let shared = DictationController()

    var state: DictationState = .idle {
        didSet { stateDidChange() }
    }
    var hasAccessibilityPermission = false
    let microphone: MicrophonePermission
    var hasMicPermission: Bool { microphone.status == .authorized }
    /// Main-actor mirror of the transcriber actor's model state, for UI.
    private(set) var sttState: TranscriptionService.ModelState = .notLoaded
    /// The text most recently inserted, shown in the HUD's done state.
    var lastInsertedText = ""
    /// The application that had focus when dictation started, preserved as the paste destination.
    private(set) var activeTargetApp: NSRunningApplication?
    /// Rolling transcript shown live in the HUD while recording. Held as a
    /// `let` so reading it registers no observation on the controller itself —
    /// only the leaf view that reads `live.text` is invalidated by a partial.
    let live = LiveTranscript()
    private var liveTask: Task<Void, Never>?

    private var hud: HUDPanelController?
    private var hudDismissTask: Task<Void, Never>?

    let coordinator = TranscriptionCoordinator()
    let recorder = AudioRecorder()
    let transcriber = TranscriptionService()
    let vocabulary = VocabularyStore()
    let history: HistoryStore
    @ObservationIgnored private var engine: CommandEngine?
    private(set) var hasStarted = false

    init(history: HistoryStore = HistoryStore(), commandEngine: CommandEngine? = nil,
         microphone: MicrophonePermission = MicrophonePermission()) {
        self.history = history
        self.engine = commandEngine
        self.microphone = microphone
    }

    var commandEngine: CommandEngine {
        if let engine { return engine }
        let engine = CommandEngine.live(controller: self)
        self.engine = engine
        return engine
    }

    /// Presents only the engine-owned request; never reconstructs or reparses a plan.
    func presentPendingConfirmation() {
        guard let request = commandEngine.pendingConfirmation else {
            state = .error("The confirmation is no longer available. Please try the command again.")
            return
        }
        state = .confirming(request)
    }

    private let hotkey = HotkeyMonitor()
    private var pressStarted: ContinuousClock.Instant?

    /// Holds shorter than this are treated as accidental taps and discarded.
    private static let minimumHold: Duration = .milliseconds(150)

    var hotkeyChoice: HotkeyChoice = {
        if let saved = UserDefaults.standard.string(forKey: "hotkeyChoice"),
           let choice = HotkeyChoice(rawValue: saved) {
            return choice
        }
        return .fn
    }() {
        didSet {
            hotkey.hotkey = hotkeyChoice
            UserDefaults.standard.set(hotkeyChoice.rawValue, forKey: "hotkeyChoice")
            armHotkey()
        }
    }

    var hotkeyLabel: String { hotkeyChoice.label }

    var writingMode: WritingMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: "writingMode"),
                  let mode = WritingMode(rawValue: raw) else {
                return .standard
            }
            return mode
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "writingMode")
        }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        hud = HUDPanelController(controller: self)
        // DailyOps is a separate product with its own bundle identifier and data domain.
        // Debug aid: `DailyOps --show-hud` displays the pill for a few
        // seconds so its rendering can be checked without dictating.
        if CommandLine.arguments.contains("--show-hud") {
            state = .recording
            hudDismissTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(6))
                self?.state = .idle
            }
        }
        if let saved = UserDefaults.standard.string(forKey: "hotkeyChoice"),
           let choice = HotkeyChoice(rawValue: saved) {
            hotkey.hotkey = choice
        }
        hotkey.onKeyDown = { [weak self] in self?.hotkeyDown() }
        hotkey.onKeyUp = { [weak self] in self?.hotkeyUp() }

        hasAccessibilityPermission = HotkeyMonitor.hasAccessibilityPermission(prompt: true)
        armHotkey()

        recorder.prewarm()

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshPermissions()
                self?.recorder.prewarm()
            }
        }

        Task { await microphone.requestIfNeeded() }

        CleanupService.prewarm(vocabulary: vocabulary.words)

        // Warm the STT model in the background so the first dictation is fast,
        // mirroring its state onto the main actor for onboarding/settings UI.
        Task {
            sttState = .loading
            await transcriber.loadModels()
            sttState = await transcriber.modelState
        }

        // Initialize Option + 1 Smart Polish Global Shortcut
        SmartPolishService.shared.start()

        if !UserDefaults.standard.bool(forKey: "hasOnboarded") {
            OnboardingWindow.show(controller: self)
        }
    }

    func setPolishing(action: String) {
        state = .polishing(action)
    }

    func completePolishing(result: String, original: String, appName: String) {
        lastInsertedText = result
        history.record(
            raw: original,
            cleaned: result,
            duration: 0,
            appName: appName
        )
        state = .done
    }

    func setTemporaryError(_ message: String) {
        state = .error(message)
    }

    private(set) var hotkeyArmed = false

    /// True only when dictation can actually work end-to-end. A listen-only
    /// event tap installs without Accessibility but receives no events, so an
    /// armed tap alone is not readiness.
    var isReady: Bool { hotkeyArmed && hasAccessibilityPermission }

    /// Installing the event tap fails until the user grants permission in
    /// System Settings — which happens outside this process, after launch.
    /// Keep retrying until the tap installs; a one-shot check at launch left
    /// the hotkey permanently dead for anyone who granted access afterwards.
    private func armHotkey() {
        hotkeyArmed = hotkey.start()
        log.info("Hotkey arm at launch: \(self.hotkeyArmed), AX: \(self.hasAccessibilityPermission)")
        guard !isReady else { return }
        Task { [weak self] in
            while let self, !self.isReady {
                try? await Task.sleep(for: .seconds(2))
                self.refreshPermissions()
                if self.isReady {
                    log.info("Hotkey ready after permission grant")
                }
            }
        }
    }

    /// Reload after the user changes the speech model in Settings.
    func reloadModel() {
        guard state == .idle || state == .done || state.isError else { return }
        sttState = .loading
        Task {
            await transcriber.reloadModels()
            sttState = await transcriber.modelState
        }
    }

    func copyLastInsertedText() {
        guard !lastInsertedText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastInsertedText, forType: .string)
    }

    func refreshPermissions() {
        let wasTrusted = hasAccessibilityPermission
        hasAccessibilityPermission = HotkeyMonitor.hasAccessibilityPermission()
        // Native authorization state can change in System Settings at any
        // time; both mirrors update together so the UI never goes stale.
        microphone.refresh()
        if hasMicPermission {
            recorder.prewarm()
        }
        guard hasStarted else { return }
        if hasAccessibilityPermission, !wasTrusted, hotkeyArmed {
            // A tap installed before the Accessibility grant stays deaf;
            // reinstall it now that events will actually be delivered.
            hotkey.stop()
        }
        hotkeyArmed = hotkey.start()
        if hotkeyArmed {
            hotkey.verifyTapHealth()
        }
    }

    private func hotkeyDown() {
        // A new dictation may start from any settled state, including the
        // brief done/error linger or pending confirmation — but never mid-pipeline.
        guard state == .idle || state == .done || state.isError || state.isConfirming else { return }
        if case .confirming(let request) = state {
            cancelPending(id: request.id)
        }
        coordinator.cancel(controller: self)
        live.reset()

        // 1. Immediately stamp the physical key-down timestamp
        let now = ContinuousClock.now
        pressStarted = now

        // 2. Authoritative recording state: HUD appears immediately without waiting for audio hardware spinup
        state = .recording
        log.info("Hotkey accepted -> entered .recording state immediately")

        // Capture target application at the exact moment dictation begins so focus changes never hijack insertion
        let frontApp = NSWorkspace.shared.frontmostApplication
        if frontApp?.bundleIdentifier != Bundle.main.bundleIdentifier {
            activeTargetApp = frontApp
        }

        if transcriber.isStreamingCapable {
            recorder.onBuffer = { [transcriber] buffer in
                let boxed = UncheckedSendable(value: buffer)
                Task { await transcriber.feed(boxed.value) }
            }
        } else {
            recorder.onBuffer = nil
        }

        let pressTime = now
        recorder.onFirstBufferReceived = {
            let elapsed = ContinuousClock.now - pressTime
            let elapsedMs = Double(elapsed.components.attoseconds) / 1e15
            log.info("First audio buffer arrived (\(elapsedMs, format: .fixed(precision: 1))ms after hotkeyDown)")
        }

        do {
            try recorder.start()
            log.info("Audio recorder started successfully")
        } catch {
            log.error("Failed to start recorder: \(error.localizedDescription)")
            recorder.onBuffer = nil
            recorder.onFirstBufferReceived = nil
            pressStarted = nil
            state = .error(error.localizedDescription)
            return
        }

        if transcriber.isStreamingCapable {
            liveTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let updates = try await self.transcriber.startStream()
                    for await text in updates {
                        // Coalesced: identical partials cost a string compare, and
                        // bursts publish at most ~16 Hz instead of every update.
                        self.live.submit(text)
                    }
                } catch {
                    // Live preview is best-effort; the batch path on release
                    // still produces the final transcript.
                    log.warning("Live streaming unavailable: \(error.localizedDescription)")
                }
            }
        }
    }

    private func hotkeyUp(simulatedHoldDuration: Duration? = nil) {
        guard state == .recording else { return }
        recorder.onBuffer = nil
        recorder.onFirstBufferReceived = nil
        let samples = recorder.stop()
        let heldDuration = simulatedHoldDuration ?? pressStarted.map { ContinuousClock.now - $0 }
        let heldLongEnough = heldDuration.map { $0 >= Self.minimumHold } ?? false
        pressStarted = nil

        liveTask?.cancel()
        liveTask = nil

        guard heldLongEnough else {
            let durationMs = heldDuration.map { Double($0.components.attoseconds) / 1e15 } ?? 0
            log.info("Discarded accidental tap (\(durationMs, format: .fixed(precision: 1))ms < 150ms)")
            live.reset()
            Task { await transcriber.cancelStream() }
            state = .idle
            return
        }

        guard !samples.isEmpty else {
            log.warning("Audio capture ended with 0 samples after valid hold")
            live.reset()
            Task { await transcriber.cancelStream() }
            state = .error("No audio captured — check microphone input.")
            return
        }

        // vDSP keeps this O(n) pass off the critical path at key-release: a
        // 30 s take is ~480k samples, and the scalar reduce ran on the main
        // actor at exactly the moment the user expects the HUD to react.
        let rms = vDSP.rootMeanSquare(samples)
        if rms < 0.001 {
            // All-zero audio means macOS is muting us: mic permission is
            // missing or stale, even though the engine runs without error.
            live.reset()
            Task { await transcriber.cancelStream() }
            state = .error("Mic captured silence — check Microphone permission for DailyOps.")
            return
        }

        coordinator.process(samples: samples, controller: self, targetApp: activeTargetApp)
    }

    #if DEBUG
    func hotkeyDownForTesting() {
        hotkeyDown()
    }

    func hotkeyUpForTesting(simulatedHoldDuration: Duration? = nil) {
        hotkeyUp(simulatedHoldDuration: simulatedHoldDuration)
    }

    func cancelPendingForTesting() {
        coordinator.cancel(controller: self)
    }
    #endif

    /// Confirms a pending confirmation request by ID and executes the validated plan.
    /// Returns true when the engine had a matching pending request. When executing
    /// the approved plan reaches another sensitive boundary, the engine registers
    /// the next request and it is displayed verbatim — never dropped to idle.
    @discardableResult
    func confirmPending(id: ConfirmationRequestID) -> Bool {
        guard case .confirming(let request) = state, request.id == id else { return false }
        let targetApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
        let result = CommandModeService.confirmPending(id: id, controller: self)
        switch result {
        case .success(let feedback):
            lastInsertedText = feedback
            history.recordCommand(
                spoken: request.title,
                summary: feedback,
                appName: targetApp
            )
            state = .done
        case .failure(let message):
            state = .error(message)
        case .confirmationRequired:
            presentPendingConfirmation()
        case .ignored:
            state = .idle
        }
        return true
    }

    /// Returns true when the engine had a matching pending request to cancel.
    @discardableResult
    func cancelPending(id: ConfirmationRequestID) -> Bool {
        guard case .confirming(let request) = state, request.id == id else { return false }
        _ = CommandModeService.cancelPending(id: id, controller: self)
        state = .idle
        return true
    }

    /// Drives HUD visibility: visible while active, lingers briefly on
    /// done/error, interactive when confirming, then returns to idle.
    private func stateDidChange() {
        hudDismissTask?.cancel()
        switch state {
        case .idle:
            hud?.setInteractive(false)
            hud?.setVisible(false)
        case .recording, .transcribing, .processing, .inserting, .cleaning, .polishing:
            hud?.setInteractive(false)
            hud?.setVisible(true)
        case .done, .error:
            hud?.setInteractive(false)
            hud?.setVisible(true)
            // Long enough to read the inserted snippet in the pill.
            let linger: Duration = state == .done ? .seconds(2) : .seconds(3)
            hudDismissTask = Task { [weak self] in
                try? await Task.sleep(for: linger)
                guard !Task.isCancelled else { return }
                self?.state = .idle
            }
        case .confirming:
            hud?.setInteractive(true)
            hud?.setVisible(true)
        }
    }
}

extension DictationState {
    var isTerminal: Bool {
        switch self {
        case .idle, .done, .error:
            return true
        default:
            return false
        }
    }

    var isError: Bool {
        if case .error = self { return true }
        return false
    }

    var isPolishing: Bool {
        if case .polishing = self { return true }
        return false
    }

    var isConfirming: Bool {
        if case .confirming = self { return true }
        return false
    }

    var menuBarSymbol: String {
        switch self {
        case .idle, .done: "waveform.circle"
        case .recording: "waveform.circle.fill"
        case .transcribing, .processing, .inserting, .cleaning, .polishing: "ellipsis.circle"
        case .confirming: "questionmark.circle"
        case .error: "exclamationmark.circle"
        }
    }
}
