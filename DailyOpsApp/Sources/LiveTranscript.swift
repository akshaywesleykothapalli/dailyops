import Foundation
import Observation

/// Live (in-flight) transcription text, deliberately kept in its own
/// observable object rather than on `DictationController`.
///
/// Two separate problems motivate the split:
///
/// 1. **Update volume.** A streaming ASR engine emits partial results many
///    times per second, and each one is a superset of the last. Publishing
///    every single one costs a SwiftUI invalidation for a change no eye can
///    resolve. `submit(_:)` drops byte-identical repeats outright and
///    coalesces bursts into at most one publish per `minimumInterval`, always
///    with a trailing publish so the newest partial is never dropped.
///
/// 2. **Invalidation blast radius.** Observation tracks per-property, so a
///    view that reads `hasText` is *not* invalidated when `text` changes. The
///    HUD gates its layout on `hasText` (which flips at most twice per
///    dictation) and reads `text` only inside a small leaf view, so a partial
///    result no longer re-evaluates the whole pill.
///
/// This object holds *only* live state. Cleanup, typography, vocabulary
/// rescoring, insertion, and persistence all belong to final transcript
/// processing in `DictationController.process(_:)` and are untouched here.
@MainActor
@Observable
final class LiveTranscript {
    /// The most recently published partial transcript. Changes often.
    private(set) var text: String = ""

    /// Whether there is any live text at all. Changes at most twice per
    /// dictation, so views may gate on it without paying for `text` churn.
    private(set) var hasText: Bool = false

    @ObservationIgnored private let minimumInterval: Duration
    @ObservationIgnored private let now: @MainActor () -> ContinuousClock.Instant
    /// Last value handed to `submit`, published or not — used to drop repeats.
    @ObservationIgnored private var lastSubmitted: String = ""
    /// Value withheld by the coalescing window, awaiting the trailing flush.
    @ObservationIgnored private var pending: String?
    @ObservationIgnored private var lastPublish: ContinuousClock.Instant?
    @ObservationIgnored private var flushTask: Task<Void, Never>?

    /// - Parameters:
    ///   - minimumInterval: Shortest gap between two publishes. 60 ms is
    ///     ~16 Hz: well under the threshold where a reader notices lag, but an
    ///     order of magnitude fewer invalidations than the raw stream.
    ///   - now: Time source, injectable so the coalescing window can be tested
    ///     without sleeping.
    init(
        minimumInterval: Duration = .milliseconds(60),
        now: @escaping @MainActor () -> ContinuousClock.Instant = { ContinuousClock.now }
    ) {
        self.minimumInterval = minimumInterval
        self.now = now
    }

    /// Feeds a partial result. Cheap: an unchanged value costs one string
    /// comparison and nothing else.
    func submit(_ candidate: String) {
        guard candidate != lastSubmitted else { return }
        lastSubmitted = candidate

        let instant = now()
        if let last = lastPublish {
            let elapsed = instant - last
            if elapsed < minimumInterval {
                pending = candidate
                scheduleFlush(after: minimumInterval - elapsed)
                return
            }
        }
        publish(candidate, at: instant)
    }

    /// Publishes whatever the coalescing window is holding, immediately.
    /// Called before the final transcript is read so the last partial is never
    /// stranded mid-window.
    func flush() {
        flushTask?.cancel()
        flushTask = nil
        guard let held = pending else { return }
        publish(held, at: now())
    }

    /// Clears all state at the start — or abort — of a dictation.
    func reset() {
        flushTask?.cancel()
        flushTask = nil
        pending = nil
        lastPublish = nil
        lastSubmitted = ""
        if !text.isEmpty { text = "" }
        if hasText { hasText = false }
    }

    private func publish(_ value: String, at instant: ContinuousClock.Instant) {
        pending = nil
        lastPublish = instant
        text = value
        let nowHasText = !value.isEmpty
        if hasText != nowHasText { hasText = nowHasText }
    }

    private func scheduleFlush(after delay: Duration) {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.flushTask = nil
            self.flush()
        }
    }
}
