@preconcurrency import AVFoundation
import Foundation

protocol SpeechEngineProvider: Actor {
    func prepare() async throws
    func transcribe(_ samples: [Float]) async throws -> String
    func transcribeFile(_ url: URL) async throws -> String
    
    // Live streaming methods (optional)
    func startStream() async throws -> AsyncStream<String>
    func feed(_ buffer: AVAudioPCMBuffer) async
    func finishStream() async throws -> String
    func cancelStream() async
}

// Default implementation for engines that don't support streaming
extension SpeechEngineProvider {
    func startStream() async throws -> AsyncStream<String> {
        throw NSError(domain: AppBrand.compactName, code: 4, userInfo: [
            NSLocalizedDescriptionKey: "Live transcription is not supported by this engine.",
        ])
    }
    
    func feed(_ buffer: AVAudioPCMBuffer) async {}
    
    func finishStream() async throws -> String { return "" }
    
    func cancelStream() async {}
}
