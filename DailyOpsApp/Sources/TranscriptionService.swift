@preconcurrency import AVFoundation
import FluidAudio
import Foundation
import WhisperKit

/// Which local speech-to-text engine transcribes dictations.
enum SpeechEngine: String, CaseIterable, Identifiable {
    /// Apple on-device speech first, then local model fallback.
    case automatic
    /// Apple SpeechAnalyzer / SpeechTranscriber on macOS 26+.
    case appleSpeech
    /// Parakeet TDT via FluidAudio: fastest, with live streaming transcript.
    case parakeet
    /// WhisperKit transcription: broader model/language range, batch-only.
    case whisper

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: "Automatic (Apple Speech + local fallback)"
        case .appleSpeech: "Apple Speech (primary)"
        case .parakeet: "Parakeet (fast, live transcript)"
        case .whisper: "Whisper (more variants)"
        }
    }
}

/// Curated WhisperKit variants (all download once from HuggingFace and run
/// on-device). Identifiers are WhisperKit model names.
enum WhisperVariant: String, CaseIterable, Identifiable {
    case tinyEn = "tiny.en"
    case baseEn = "base.en"
    case smallEn = "small.en"
    case tiny
    case base
    case small
    case largeV3Turbo = "large-v3-v20240930_turbo"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tinyEn: "Tiny (English) — fastest"
        case .baseEn: "Base (English)"
        case .smallEn: "Small (English) — accurate"
        case .tiny: "Tiny (multilingual)"
        case .base: "Base (multilingual)"
        case .small: "Small (multilingual)"
        case .largeV3Turbo: "Large v3 Turbo — best quality"
        }
    }
}

/// Loads and runs the configured speech engine. All models are downloaded
/// once from HuggingFace, cached locally, and run fully on-device.
actor TranscriptionService {
    enum ModelState: Equatable {
        case notLoaded
        case loading
        case ready
        case failed(String)
    }

    private var currentEngine: SpeechEngineProvider?
    private var activeEngineType: SpeechEngine?
    private(set) var modelState: ModelState = .notLoaded

    static var configuredEngine: SpeechEngine {
        SpeechEngine(rawValue: UserDefaults.standard.string(forKey: "sttEngine") ?? "") ?? .automatic
    }

    /// Parakeet: v3 covers 25 languages, v2 is English-only with slightly
    /// better English recall.
    static var configuredVersion: AsrModelVersion {
        UserDefaults.standard.string(forKey: "sttModelVersion") == "v2" ? .v2 : .v3
    }

    static var configuredWhisperVariant: WhisperVariant {
        WhisperVariant(rawValue: UserDefaults.standard.string(forKey: "whisperModel") ?? "") ?? .baseEn
    }

    /// Whisper language hint ("auto" lets the model detect — best for
    /// code-switched speech like Hinglish; a fixed code pins the language).
    static var configuredWhisperLanguage: String {
        UserDefaults.standard.string(forKey: "whisperLanguage") ?? "auto"
    }

    /// Tears down the loaded engine and loads the currently configured one
    /// (downloading it on first use).
    func reloadModels() async {
        currentEngine = nil
        activeEngineType = nil
        modelState = .notLoaded
        await loadModels()
    }

    func loadModels() async {
        guard modelState == .notLoaded || modelState.isFailed else { return }
        modelState = .loading
        do {
            switch Self.configuredEngine {
            case .automatic:
                try await loadAutomatic()
            case .appleSpeech:
                let engine = AppleSpeechService()
                try await engine.prepare()
                currentEngine = engine
                activeEngineType = .appleSpeech
                log.info("Apple Speech model loaded")
            case .parakeet:
                let engine = ParakeetService()
                try await engine.prepare()
                currentEngine = engine
                activeEngineType = .parakeet
                log.info("Parakeet model loaded")
            case .whisper:
                let engine = WhisperService()
                try await engine.prepare()
                currentEngine = engine
                activeEngineType = .whisper
                log.info("Whisper model loaded")
            }
            modelState = .ready
        } catch {
            modelState = .failed(error.localizedDescription)
            log.error("Speech model load failed: \(error.localizedDescription)")
        }
    }

    private func loadAutomatic() async throws {
        do {
            let engine = AppleSpeechService()
            try await engine.prepare()
            currentEngine = engine
            activeEngineType = .appleSpeech
            log.info("Apple Speech model loaded for automatic mode")
            return
        } catch {
            log.warning("Apple Speech unavailable, falling back to Parakeet: \(error.localizedDescription)")
        }

        do {
            let engine = ParakeetService()
            try await engine.prepare()
            currentEngine = engine
            activeEngineType = .parakeet
            log.info("Parakeet model loaded for automatic mode")
            return
        } catch {
            log.warning("Parakeet unavailable, falling back to Whisper: \(error.localizedDescription)")
        }

        let engine = WhisperService()
        try await engine.prepare()
        currentEngine = engine
        activeEngineType = .whisper
        log.info("Whisper model loaded for automatic mode")
    }

    // MARK: - Live streaming (Parakeet only)

    /// Begins a live session and returns a stream of the full transcript so
    /// far (confirmed + volatile), refreshed roughly every second.
    ///
    /// A fresh SlidingWindowAsrManager per dictation: its input stream is
    /// single-use (finish() terminates it permanently), and the CoreML models
    /// are shared via the cached AsrModels, so per-session setup is cheap.
    ///
    /// Whisper has no streaming path here; dictations transcribe in one
    /// batch on release, and the HUD simply shows no live text.
    func startStream() async throws -> AsyncStream<String> {
        if modelState != .ready {
            await loadModels()
        }
        guard activeEngineType == .parakeet else {
            throw NSError(domain: AppBrand.compactName, code: 4, userInfo: [
                NSLocalizedDescriptionKey: "Live transcription is only available with the Parakeet engine.",
            ])
        }
        guard let currentEngine else {
            throw notReadyError
        }
        return try await currentEngine.startStream()
    }

    nonisolated var isStreamingCapable: Bool {
        switch Self.configuredEngine {
        case .parakeet: return true
        case .automatic, .appleSpeech, .whisper: return false
        }
    }

    func isStreamingActive() -> Bool {
        activeEngineType == .parakeet
    }

    func feed(_ buffer: AVAudioPCMBuffer) async {
        guard activeEngineType == .parakeet else { return }
        await currentEngine?.feed(buffer)
    }

    func finishStream() async throws -> String {
        guard activeEngineType == .parakeet else { return "" }
        guard let currentEngine else { return "" }
        return try await currentEngine.finishStream()
    }

    func cancelStream() async {
        await currentEngine?.cancelStream()
    }

    // MARK: - Batch transcription

    func transcribeFile(_ url: URL) async throws -> String {
        guard !Task.isCancelled else { throw CancellationError() }
        try await ensureReady()
        guard !Task.isCancelled else { throw CancellationError() }
        guard let currentEngine else { throw notReadyError }
        return try await currentEngine.transcribeFile(url)
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        guard !Task.isCancelled else { throw CancellationError() }
        try await ensureReady()
        guard !Task.isCancelled else { throw CancellationError() }
        guard let currentEngine else { throw notReadyError }
        return try await currentEngine.transcribe(samples)
    }

    private func ensureReady() async throws {
        if modelState != .ready {
            await loadModels()
        }
        guard modelState == .ready else { throw notReadyError }
    }

    private var notReadyError: NSError {
        NSError(domain: AppBrand.compactName, code: 3, userInfo: [
            NSLocalizedDescriptionKey: "Speech model is not ready yet.",
        ])
    }


}

extension TranscriptionService.ModelState {
    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}
