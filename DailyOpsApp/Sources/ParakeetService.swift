@preconcurrency import AVFoundation
import FluidAudio

actor ParakeetService: SpeechEngineProvider {
    private var manager: AsrManager?
    private var models: AsrModels?
    private var streamer: SlidingWindowAsrManager?
    
    private var version: AsrModelVersion {
        TranscriptionService.configuredVersion
    }
    
    func prepare() async throws {
        let models = try await AsrModels.downloadAndLoad(version: version)
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        self.models = models
        self.manager = manager
    }
    
    func transcribe(_ samples: [Float]) async throws -> String {
        guard !Task.isCancelled else { throw CancellationError() }
        guard let manager else { throw notReadyError }
        var decoderState = try TdtDecoderState()
        let result = try await manager.transcribe(samples, decoderState: &decoderState)
        guard !Task.isCancelled else { throw CancellationError() }
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func transcribeFile(_ url: URL) async throws -> String {
        guard !Task.isCancelled else { throw CancellationError() }
        guard let manager else { throw notReadyError }
        var decoderState = try TdtDecoderState()
        let result = try await manager.transcribe(url, decoderState: &decoderState)
        guard !Task.isCancelled else { throw CancellationError() }
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func startStream() async throws -> AsyncStream<String> {
        guard let models else { throw notReadyError }
        await streamer?.cancel()
        
        let streamer = SlidingWindowAsrManager(config: .streaming)
        try await streamer.loadModels(models)
        let rawUpdates = await streamer.transcriptionUpdates
        try await streamer.startStreaming(source: .microphone)
        self.streamer = streamer
        
        return AsyncStream { continuation in
            let task = Task {
                // The engine re-emits on every decode step, and most steps
                // leave the combined text unchanged. Yielding those costs a
                // main-actor hop and a SwiftUI invalidation for no visible
                // difference, so identical values are dropped here — at the
                // source — rather than downstream.
                var lastYielded: String?
                for await _ in rawUpdates {
                    let confirmed = await streamer.confirmedTranscript
                    let volatile = await streamer.volatileTranscript
                    let combined: String
                    if confirmed.isEmpty {
                        combined = volatile
                    } else if volatile.isEmpty {
                        combined = confirmed
                    } else {
                        combined = confirmed + " " + volatile
                    }
                    guard combined != lastYielded else { continue }
                    lastYielded = combined
                    continuation.yield(combined)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    
    func feed(_ buffer: AVAudioPCMBuffer) async {
        await streamer?.streamAudio(buffer)
    }
    
    func finishStream() async throws -> String {
        guard !Task.isCancelled else { throw CancellationError() }
        guard let streamer else { return "" }
        self.streamer = nil
        let text = try await withTaskCancellationHandler {
            try await streamer.finish()
        } onCancel: {
            Task { await streamer.cancel() }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func cancelStream() async {
        await streamer?.cancel()
        streamer = nil
    }
    
    private var notReadyError: NSError {
        NSError(domain: AppBrand.compactName, code: 3, userInfo: [
            NSLocalizedDescriptionKey: "Parakeet model is not ready yet.",
        ])
    }
}
