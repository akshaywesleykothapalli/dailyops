import AppKit
@preconcurrency import AVFoundation

/// Accumulates converted samples across the realtime audio thread.
/// AVAudioEngine tap callbacks run off the main actor, so this box is the
/// only piece the audio thread writes to.
private final class SampleBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []

    func append(_ newSamples: [Float]) {
        lock.lock()
        samples.append(contentsOf: newSamples)
        lock.unlock()
    }

    func drain() -> [Float] {
        lock.lock()
        defer { samples = []; lock.unlock() }
        return samples
    }
}

/// Hands a single buffer to AVAudioConverter's pull-style input block.
/// The block is @Sendable, so the one-shot state lives in this box.
private final class OneShotInput: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?
    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }

    func take() -> AVAudioPCMBuffer? {
        defer { buffer = nil }
        return buffer
    }
}

/// All state the realtime tap callback touches, isolated from the main actor.
/// The tap closure must be @Sendable: a plain closure formed in a @MainActor
/// method inherits MainActor isolation and the runtime traps the moment
/// CoreAudio invokes it on the audio thread (dispatch_assert_queue_fail).
private final class TapProcessor: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let outFormat: AVAudioFormat
    private let ratio: Double
    private let samples: SampleBuffer
    private let onLevel: @Sendable (Float) -> Void
    private let onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?
    private let onFirstBuffer: (@Sendable () -> Void)?
    private var hasDeliveredFirstBuffer = false

    init(
        converter: AVAudioConverter,
        outFormat: AVAudioFormat,
        inputSampleRate: Double,
        samples: SampleBuffer,
        onLevel: @escaping @Sendable (Float) -> Void,
        onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?,
        onFirstBuffer: (@Sendable () -> Void)? = nil
    ) {
        self.converter = converter
        self.outFormat = outFormat
        self.ratio = AudioRecorder.sampleRate / inputSampleRate
        self.samples = samples
        self.onLevel = onLevel
        self.onBuffer = onBuffer
        self.onFirstBuffer = onFirstBuffer
    }

    func process(_ pcmBuffer: AVAudioPCMBuffer) {
        if !hasDeliveredFirstBuffer {
            hasDeliveredFirstBuffer = true
            onFirstBuffer?()
        }
        onBuffer?(pcmBuffer)
        let capacity = AVAudioFrameCount(Double(pcmBuffer.frameLength) * ratio) + 16
        guard let converted = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return }

        let input = OneShotInput(pcmBuffer)
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, outStatus in
            if let buffer = input.take() {
                outStatus.pointee = .haveData
                return buffer
            }
            outStatus.pointee = .noDataNow
            return nil
        }
        guard error == nil, converted.frameLength > 0, let data = converted.floatChannelData else { return }

        let chunk = Array(UnsafeBufferPointer(start: data[0], count: Int(converted.frameLength)))
        samples.append(chunk)
        onLevel(sqrt(chunk.reduce(0) { $0 + $1 * $1 } / Float(chunk.count)))
    }

    func flush() {
        guard let drainBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: 2048) else { return }
        var error: NSError?
        converter.convert(to: drainBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .endOfStream
            return nil
        }
        guard error == nil, drainBuffer.frameLength > 0, let data = drainBuffer.floatChannelData else { return }
        let tailChunk = Array(UnsafeBufferPointer(start: data[0], count: Int(drainBuffer.frameLength)))
        samples.append(tailChunk)
    }
}

/// Captures microphone input and converts it to 16 kHz mono Float32,
/// the input format Parakeet expects. Publishes an RMS level for the HUD.
@MainActor
@Observable
final class AudioRecorder {
    nonisolated static let sampleRate: Double = 16000

    private(set) var level: Float = 0
    private(set) var isRecording = false

    /// Raw mic buffers, delivered on the audio thread — set before start().
    /// Consumers (the streaming transcriber) resample themselves.
    var onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?

    /// Diagnostic callback when the first audio buffer is processed.
    var onFirstBufferReceived: (@Sendable () -> Void)?

    @ObservationIgnored private lazy var engine = AVAudioEngine()
    private let buffer = SampleBuffer()
    private var currentProcessor: TapProcessor?
    private nonisolated(unsafe) var configObserver: (any NSObjectProtocol)?
    private nonisolated(unsafe) var wakeObserver: (any NSObjectProtocol)?

    init() {
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleEngineConfigurationChange()
            }
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleEngineConfigurationChange()
            }
        }
    }

    deinit {
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
        }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    static func requestMicPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    /// Prewarms the audio engine and input node off the critical hotkey path
    /// so the first dictation does not block on AUHAL initialization.
    func prewarm() {
        guard !isRecording else { return }
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0 else { return }
        engine.prepare()
        log.info("Audio engine prewarmed (sampleRate: \(inFormat.sampleRate)Hz, channels: \(inFormat.channelCount))")
    }

    private func handleEngineConfigurationChange() {
        log.info("Audio engine configuration changed or system woke from sleep")
        guard !isRecording else { return }
        engine.stop()
        engine.reset()
        prewarm()
    }

    func start() throws {
        guard !isRecording else { return }
        _ = buffer.drain()

        var input = engine.inputNode
        var inFormat = input.outputFormat(forBus: 0)

        // If the format is invalid or engine graph is stale (e.g. after sleep/wake),
        // reset the engine and re-query.
        if inFormat.sampleRate <= 0 {
            engine.reset()
            input = engine.inputNode
            inFormat = input.outputFormat(forBus: 0)
        }

        guard inFormat.sampleRate > 0 else {
            throw NSError(domain: AppBrand.compactName, code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No microphone input available.",
            ])
        }
        let outFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: false
        )!
        guard let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
            throw NSError(domain: AppBrand.compactName, code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Could not convert microphone format.",
            ])
        }

        let processor = TapProcessor(
            converter: converter,
            outFormat: outFormat,
            inputSampleRate: inFormat.sampleRate,
            samples: buffer,
            onLevel: { [weak self] rms in
                Task { @MainActor in self?.level = rms }
            },
            onBuffer: onBuffer,
            onFirstBuffer: onFirstBufferReceived
        )
        currentProcessor = processor

        // Explicitly @Sendable so the closure carries no MainActor isolation
        // onto the realtime audio thread.
        let tapBlock: @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void = { pcmBuffer, _ in
            processor.process(pcmBuffer)
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat, block: tapBlock)

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            currentProcessor = nil
            level = 0
            throw error
        }
        isRecording = true
    }

    func stop() -> [Float] {
        guard isRecording else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        currentProcessor?.flush()
        currentProcessor = nil
        isRecording = false
        level = 0
        let samples = buffer.drain()
        // Prepare engine immediately for the next dictation
        engine.prepare()
        return samples
    }

    func cancel() {
        guard isRecording else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        currentProcessor = nil
        isRecording = false
        level = 0
        _ = buffer.drain()
        engine.prepare()
    }
}
