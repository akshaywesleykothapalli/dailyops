@preconcurrency import AVFoundation
import Foundation
import WhisperKit

actor WhisperService: SpeechEngineProvider {
    private var whisper: WhisperKit?
    
    private var variant: WhisperVariant {
        TranscriptionService.configuredWhisperVariant
    }
    
    private var decodeOptions: DecodingOptions {
        let language = TranscriptionService.configuredWhisperLanguage
        guard language != "auto" else { return DecodingOptions() }
        return DecodingOptions(language: language, usePrefillPrompt: true)
    }
    
    func prepare() async throws {
        whisper = try await WhisperKit(WhisperKitConfig(model: variant.rawValue))
    }
    
    func transcribe(_ samples: [Float]) async throws -> String {
        guard !Task.isCancelled else { throw CancellationError() }
        guard let whisper else { throw notReadyError }
        let results = try await whisper.transcribe(audioArray: samples, decodeOptions: decodeOptions)
        guard !Task.isCancelled else { throw CancellationError() }
        return joined(results)
    }
    
    func transcribeFile(_ url: URL) async throws -> String {
        guard !Task.isCancelled else { throw CancellationError() }
        guard let whisper else { throw notReadyError }
        let results = try await whisper.transcribe(audioPath: url.path, decodeOptions: decodeOptions)
        guard !Task.isCancelled else { throw CancellationError() }
        return joined(results)
    }
    
    private var notReadyError: NSError {
        NSError(domain: AppBrand.compactName, code: 3, userInfo: [
            NSLocalizedDescriptionKey: "Whisper model is not ready yet.",
        ])
    }
    
    private func joined(_ results: [TranscriptionResult]) -> String {
        results.map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
