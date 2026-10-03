@preconcurrency import AVFoundation
import Foundation
import Speech

actor AppleSpeechService: SpeechEngineProvider {
    private var preparedLocale: Locale?

    func prepare() async throws {
        guard #available(macOS 26.0, *) else {
            throw NSError(domain: AppBrand.compactName, code: 20, userInfo: [
                NSLocalizedDescriptionKey: "Apple Speech requires macOS 26 or later.",
            ])
        }

        let locale = await Self.preferredLocale()
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        let modules: [any SpeechModule] = [transcriber]
        let status = await AssetInventory.status(forModules: modules)

        switch status {
        case .installed:
            break
        case .supported, .downloading:
            if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
                try await request.downloadAndInstall()
            } else {
                _ = try await AssetInventory.reserve(locale: locale)
            }
        case .unsupported:
            throw NSError(domain: AppBrand.compactName, code: 21, userInfo: [
                NSLocalizedDescriptionKey: "Apple Speech is not available for this language on this Mac.",
            ])
        @unknown default:
            throw NSError(domain: AppBrand.compactName, code: 22, userInfo: [
                NSLocalizedDescriptionKey: "Apple Speech is not available right now.",
            ])
        }

        let analyzer = SpeechAnalyzer(modules: modules, options: .init(priority: .userInitiated, modelRetention: .lingering))
        try await analyzer.prepareToAnalyze(in: nil)
        preparedLocale = locale
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        guard samples.count >= 1600 else { return "" }
        let sampleRate = AudioRecorder.sampleRate
        let url = try Self.writeTemporaryAudioFile(samples: samples, sampleRate: sampleRate)
        defer { try? FileManager.default.removeItem(at: url) }
        return try await transcribeFile(url)
    }

    func transcribeFile(_ url: URL) async throws -> String {
        guard #available(macOS 26.0, *) else {
            throw NSError(domain: AppBrand.compactName, code: 20, userInfo: [
                NSLocalizedDescriptionKey: "Apple Speech requires macOS 26 or later.",
            ])
        }
        if preparedLocale == nil {
            try await prepare()
        }
        let locale: Locale
        if let preparedLocale {
            locale = preparedLocale
        } else {
            locale = await Self.preferredLocale()
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        let audioFile = try AVAudioFile(forReading: url)
        guard audioFile.length > 0 else { return "" }
        let analyzer = SpeechAnalyzer(modules: [transcriber], options: .init(priority: .userInitiated, modelRetention: .whileInUse))

        let collector = Task<String, Error> {
            var finalSegments: [String] = []
            var latestVolatile: String = ""

            for try await result in transcriber.results {
                if Task.isCancelled { break }
                let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                if result.isFinal {
                    finalSegments.append(text)
                    latestVolatile = ""
                } else {
                    latestVolatile = text
                }
            }
            let allSegments = finalSegments + (latestVolatile.isEmpty ? [] : [latestVolatile])
            return allSegments.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        do {
            try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
            let transcript = try await withTaskCancellationHandler {
                try await collector.value
            } onCancel: {
                collector.cancel()
                Task { await analyzer.cancelAndFinishNow() }
            }
            return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            collector.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }

    private static func preferredLocale() async -> Locale {
        let current = Locale.current
        if #available(macOS 26.0, *) {
            if let supported = await SpeechTranscriber.supportedLocale(equivalentTo: current) {
                return supported
            }
        }
        return Locale(identifier: "en_US")
    }

    private static func writeTemporaryAudioFile(samples: [Float], sampleRate: Double) throws -> URL {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            throw NSError(domain: AppBrand.compactName, code: 23, userInfo: [
                NSLocalizedDescriptionKey: "Could not prepare audio for Apple Speech.",
            ])
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { pointer in
            buffer.floatChannelData?[0].update(from: pointer.baseAddress!, count: samples.count)
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(AppBrand.compactName)-\(UUID().uuidString)")
            .appendingPathExtension("caf")
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }
}
