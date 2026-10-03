import AppKit
import Foundation
import os

private let coordLog = Logger(subsystem: AppBrand.bundleIdentifier, category: "coordinator")

/// Privacy-safe diagnostic timing record for dictation lifecycle.
/// NEVER logs transcript text, clipboard content, or audio samples.
public struct DictationDiagnostics: Sendable {
    public let recordingDuration: Double
    public let audioDuration: Double
    public let audioFrames: Int
    public let audioBufferSize: Int
    public let transcriptionDuration: Double
    public let processingDuration: Double
    public let insertionDuration: Double
    public let totalLatency: Double
    public let modelUsed: String
    public let wordCount: Int
    public let characterCount: Int

    public init(
        recordingDuration: Double,
        audioDuration: Double,
        audioFrames: Int,
        audioBufferSize: Int,
        transcriptionDuration: Double,
        processingDuration: Double,
        insertionDuration: Double,
        totalLatency: Double,
        modelUsed: String,
        wordCount: Int,
        characterCount: Int
    ) {
        self.recordingDuration = recordingDuration
        self.audioDuration = audioDuration
        self.audioFrames = audioFrames
        self.audioBufferSize = audioBufferSize
        self.transcriptionDuration = transcriptionDuration
        self.processingDuration = processingDuration
        self.insertionDuration = insertionDuration
        self.totalLatency = totalLatency
        self.modelUsed = modelUsed
        self.wordCount = wordCount
        self.characterCount = characterCount
    }

    public func logDiagnostic(logger: Logger) {
        logger.info("""
        Dictation:
        duration=\(String(format: "%.1f", self.recordingDuration))s
        words=\(self.wordCount)
        audioFrames=\(self.audioFrames)
        transcription=\(String(format: "%.2f", self.transcriptionDuration))s
        processing=\(String(format: "%.2f", self.processingDuration))s
        insertion=\(String(format: "%.2f", self.insertionDuration))s
        total=\(String(format: "%.2f", self.totalLatency))s
        model=\(self.modelUsed)
        chars=\(self.characterCount)
        """)
    }
}

/// Manages the transcription execution lifecycle with guaranteed terminal states,
/// explicit cancellation, timeout protection, session isolation, and structured concurrency.
@MainActor
public final class TranscriptionCoordinator {
    private var inFlightTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private(set) var currentSessionID: UInt64 = 0
    private let pasteService: PasteServing
    private let promptDetector: PromptContextDetecting
    private let timeout: Duration

    /// Maximum time allowed for transcription before forcing a terminal error state.
    public static let transcriptionTimeout: Duration = .seconds(12)

    public init(
        pasteService: PasteServing = PasteService.shared,
        promptDetector: PromptContextDetecting = PromptContextDetector.shared,
        timeout: Duration = TranscriptionCoordinator.transcriptionTimeout
    ) {
        self.pasteService = pasteService
        self.promptDetector = promptDetector
        self.timeout = timeout
    }

    /// Cancels any currently executing transcription and resets to idle.
    func cancel(controller: DictationController) {
        currentSessionID &+= 1
        watchdogTask?.cancel()
        watchdogTask = nil
        if let task = inFlightTask {
            task.cancel()
            inFlightTask = nil
        }
        controller.recorder.cancel()
        Task { await controller.transcriber.cancelStream() }
        controller.state = .idle
    }

    /// Starts processing audio samples with guaranteed terminal state.
    func process(
        samples: [Float],
        controller: DictationController,
        targetApp: NSRunningApplication? = nil
    ) {
        // Immediate synchronous transition to transcribing
        controller.state = .transcribing

        // Invalidate and cancel any existing in-flight task to prevent duplicate/overlapping sessions
        currentSessionID &+= 1
        let sessionID = currentSessionID

        watchdogTask?.cancel()
        watchdogTask = nil
        inFlightTask?.cancel()
        inFlightTask = nil

        // If samples are empty and no hypothesis exists, immediately settle to idle
        controller.live.flush()
        let hypothesis = controller.live.text
        if samples.isEmpty && hypothesis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            controller.state = .idle
            return
        }

        // Independent safety watchdog: forces recovery if the pipeline does not reach a terminal state
        watchdogTask = Task { [weak self, weak controller] in
            guard let self else { return }
            try? await Task.sleep(for: self.timeout)
            guard !Task.isCancelled else { return }
            guard let controller else { return }
            guard self.currentSessionID == sessionID else { return }

            coordLog.error("Transcription safety watchdog fired for session \(sessionID). Forcing recovery.")

            // 1. Invalidate session so late tasks never mutate state or paste
            self.currentSessionID &+= 1

            // 2. Cancel in-flight task
            self.inFlightTask?.cancel()
            self.inFlightTask = nil

            // 3. Cancel underlying stream
            Task { await controller.transcriber.cancelStream() }

            // 4. Force state to error
            controller.state = .error("Transcription timed out. Please try again.")
        }

        inFlightTask = Task { [weak self, weak controller] in
            guard let self, let controller else { return }
            await self.executePipeline(
                samples: samples,
                controller: controller,
                targetApp: targetApp,
                sessionID: sessionID,
                hypothesis: hypothesis
            )
            if self.currentSessionID == sessionID {
                self.inFlightTask = nil
                self.watchdogTask?.cancel()
                self.watchdogTask = nil
            }
        }
    }

    private func executePipeline(
        samples: [Float],
        controller: DictationController,
        targetApp: NSRunningApplication?,
        sessionID: UInt64,
        hypothesis: String
    ) async {
        guard sessionID == currentSessionID, !Task.isCancelled else { return }

        let targetContext = promptDetector.currentTargetContext(for: targetApp)
        let words = controller.vocabulary.words
        let isFormal = controller.writingMode == .formal

        let pipelineStart = ContinuousClock.now

        do {
            try await self.runTranscriptionPipeline(
                samples: samples,
                controller: controller,
                targetApp: targetApp,
                targetContext: targetContext,
                hypothesis: hypothesis,
                isFormal: isFormal,
                words: words,
                sessionID: sessionID,
                pipelineStart: pipelineStart
            )
        } catch is CancellationError {
            coordLog.info("Transcription session \(sessionID) cancelled")
            if sessionID == self.currentSessionID && !controller.state.isTerminal {
                controller.state = .idle
            }
        } catch {
            coordLog.error("Transcription session \(sessionID) failed: \(error.localizedDescription)")
            if sessionID == self.currentSessionID {
                controller.state = .error(error.localizedDescription)
            }
        }

        // Failsafe: Ensure state ALWAYS reaches a valid terminal state
        if sessionID == self.currentSessionID && !controller.state.isTerminal {
            coordLog.warning("Failsafe: State was not terminal after pipeline; resetting to idle")
            controller.state = .idle
        }
    }

    private func runTranscriptionPipeline(
        samples: [Float],
        controller: DictationController,
        targetApp: NSRunningApplication?,
        targetContext: TargetAppContext,
        hypothesis: String,
        isFormal: Bool,
        words: [String],
        sessionID: UInt64,
        pipelineStart: ContinuousClock.Instant
    ) async throws {
        guard sessionID == currentSessionID, !Task.isCancelled else { throw CancellationError() }

        let tTranscribeStart = ContinuousClock.now

        // 1. Fetch transcript from streaming engine or batch transcriber
        var raw = ""
        let isStreaming = await controller.transcriber.isStreamingActive()
        if isStreaming {
            // Attempt to finish active stream with a bounded timeout (3s)
            raw = (try? await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    try await controller.transcriber.finishStream()
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(3))
                    throw CancellationError()
                }
                let res = try await group.next()!
                group.cancelAll()
                return res
            }) ?? ""
        }

        // If streaming produced no output, fallback to live hypothesis if non-empty, or batch transcribe
        if raw.isEmpty {
            let trimmedHypothesis = hypothesis.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedHypothesis.isEmpty {
                raw = trimmedHypothesis
            } else {
                guard sessionID == currentSessionID, !Task.isCancelled else { throw CancellationError() }
                raw = try await controller.transcriber.transcribe(samples)
            }
        }

        let tTranscribeEnd = ContinuousClock.now

        guard sessionID == currentSessionID, !Task.isCancelled else { throw CancellationError() }

        // 2. Validate non-empty transcript
        let trimmedRaw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRaw.isEmpty else {
            if sessionID == currentSessionID {
                controller.state = .idle
            }
            return
        }

        let tProcessStart = ContinuousClock.now
        controller.state = .processing

        // 3. Vocabulary Rescoring & custom replacements
        var processed = VocabularyRescorer.rescore(
            trimmedRaw,
            vocabulary: controller.vocabulary.words,
            replacements: controller.vocabulary.replacements
        )
        processed = controller.vocabulary.applyReplacements(to: processed)

        // 4. Duplicate Speech Detection (Phase 9)
        processed = DuplicateSpeechDetector.process(processed)

        guard sessionID == currentSessionID, !Task.isCancelled else { throw CancellationError() }

        // 5. Command Mode Evaluation (Phase 7)
        let outcome = await CommandModeService.processTranscriptAsync(processed, controller: controller)
        guard sessionID == currentSessionID, !Task.isCancelled else { throw CancellationError() }

        switch outcome {
        case .executed(let feedback):
            controller.lastInsertedText = feedback
            controller.history.recordCommand(
                spoken: processed,
                summary: feedback,
                appName: targetContext.localizedName
            )
            controller.state = .done
            return

        case .confirmationRequired(let request):
            controller.state = .confirming(request)
            return

        case .failed(let message):
            controller.state = .error(message)
            return

        case .ignored:
            break
        }

        // 6. Formatting, Tone, and Prompt-Aware Processing
        let cleaned: String
        if targetContext.isPromptOriented {
            cleaned = PromptInputProcessor.processPromptText(processed, protectedWords: words)
        } else if isFormal {
            controller.state = .cleaning
            if AppleWritingToolsService.isAvailable {
                let formalResult = await AppleWritingToolsService.transform(processed, action: .formal, vocabulary: words)
                cleaned = TranscriptFormatter.format(controller.vocabulary.applyReplacements(to: formalResult), protectedWords: words)
            } else {
                let formalResult = await CleanupService.clean(processed, vocabulary: words, formal: true)
                cleaned = TranscriptFormatter.format(controller.vocabulary.applyReplacements(to: formalResult), protectedWords: words)
            }
        } else {
            if CleanupService.isEnabled && (CleanupService.alwaysPolish || CleanupService.needsRewrite(processed)) {
                controller.state = .cleaning
                if AppleWritingToolsService.isAvailable {
                    let polished = await AppleWritingToolsService.transform(processed, action: .rewrite, vocabulary: words)
                    cleaned = TranscriptFormatter.format(controller.vocabulary.applyReplacements(to: polished), protectedWords: words)
                } else {
                    let polished = await CleanupService.clean(processed, vocabulary: words, formal: false)
                    cleaned = TranscriptFormatter.format(controller.vocabulary.applyReplacements(to: polished), protectedWords: words)
                }
            } else {
                cleaned = TranscriptFormatter.format(processed, protectedWords: words)
            }
        }

        let tProcessEnd = ContinuousClock.now

        guard sessionID == currentSessionID, !Task.isCancelled else { throw CancellationError() }

        // 7. Text Insertion via PasteService
        controller.lastInsertedText = cleaned
        controller.state = .inserting
        let tInsertStart = ContinuousClock.now
        let pasteResult = await pasteService.insert(cleaned, targetApp: targetApp)
        let tInsertEnd = ContinuousClock.now

        guard sessionID == currentSessionID, !Task.isCancelled else { throw CancellationError() }

        // 8. History Persistence
        controller.history.record(
            raw: processed,
            cleaned: cleaned,
            duration: Double(samples.count) / AudioRecorder.sampleRate,
            appName: targetContext.localizedName
        )

        // 9. Final Terminal UI State
        switch pasteResult {
        case .success:
            controller.state = .done
        case .copiedToClipboard(let message):
            controller.lastInsertedText = message
            controller.state = .done
        case .failure(let reason):
            controller.state = .error(reason.description)
        }

        // 10. Privacy-Safe Diagnostic Timing Instrumentation
        let totalElapsed = pipelineStart.duration(to: ContinuousClock.now)
        let transcribeElapsed = tTranscribeStart.duration(to: tTranscribeEnd)
        let processElapsed = tProcessStart.duration(to: tProcessEnd)
        let insertElapsed = tInsertStart.duration(to: tInsertEnd)
        let audioDuration = Double(samples.count) / AudioRecorder.sampleRate
        let wordCount = cleaned.split(whereSeparator: \.isWhitespace).count

        let diagnostics = DictationDiagnostics(
            recordingDuration: audioDuration,
            audioDuration: audioDuration,
            audioFrames: samples.count,
            audioBufferSize: samples.count * MemoryLayout<Float>.size,
            transcriptionDuration: Double(transcribeElapsed.components.seconds) + Double(transcribeElapsed.components.attoseconds) * 1e-18,
            processingDuration: Double(processElapsed.components.seconds) + Double(processElapsed.components.attoseconds) * 1e-18,
            insertionDuration: Double(insertElapsed.components.seconds) + Double(insertElapsed.components.attoseconds) * 1e-18,
            totalLatency: Double(totalElapsed.components.seconds) + Double(totalElapsed.components.attoseconds) * 1e-18,
            modelUsed: TranscriptionService.configuredEngine.rawValue,
            wordCount: wordCount,
            characterCount: cleaned.count
        )
        diagnostics.logDiagnostic(logger: coordLog)
    }
}
