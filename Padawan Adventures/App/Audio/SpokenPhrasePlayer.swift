import AVFoundation
import Foundation

/// Speaks a short gameplay phrase via system TTS (placeholder until recorded VO),
/// ducking music and ambience loops for the duration.
@MainActor
final class SpokenPhrasePlayer: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = SpokenPhrasePlayer()

    /// Music/loop duck is re-armed on this cadence while speech is in flight.
    private static let duckRearmSeconds: TimeInterval = 0.3
    private static let duckHoldSeconds: TimeInterval = 0.6

    private let synthesizer = AVSpeechSynthesizer()
    private var completion: (() -> Void)?
    private var duckTask: Task<Void, Never>?
    /// Identifies the utterance the stored `completion` belongs to. Delegate
    /// callbacks arrive asynchronously, so a cancelled utterance can report back
    /// after the next `speak` has already installed its completion.
    private var activeUtteranceID: ObjectIdentifier?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speaks `text`, calling `completion` when the utterance finishes or is cancelled.
    /// Calls `completion` immediately when speech is muted or the text is blank.
    func speak(_ text: String, completion: (() -> Void)? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let volume = SoundEffectsController.shared.soundEffectsVolume
        guard !trimmed.isEmpty, volume > 0 else {
            completion?()
            return
        }
        synthesizer.stopSpeaking(at: .immediate)
        finish()
        self.completion = completion
        startDucking()
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = volume
        activeUtteranceID = ObjectIdentifier(utterance)
        synthesizer.speak(utterance)
    }

    /// Stops any in-flight speech and its music duck without running the pending
    /// completion. Call when the caller's scene goes away.
    func cancel() {
        // Cleared first so the asynchronous `didCancel` below is ignored.
        activeUtteranceID = nil
        completion = nil
        duckTask?.cancel()
        duckTask = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func startDucking() {
        duckTask?.cancel()
        duckTask = Task { @MainActor in
            while !Task.isCancelled {
                SoundEffectsController.shared.duckAmbience(for: Self.duckHoldSeconds)
                try? await Task.sleep(
                    nanoseconds: UInt64(Self.duckRearmSeconds * 1_000_000_000)
                )
            }
        }
    }

    private func finish() {
        duckTask?.cancel()
        duckTask = nil
        activeUtteranceID = nil
        let done = completion
        completion = nil
        done?()
    }

    /// Ignores callbacks for an utterance that `speak` has already superseded,
    /// which would otherwise fire the *next* request's completion early.
    private func finish(if utteranceID: ObjectIdentifier) {
        guard activeUtteranceID == utteranceID else { return }
        finish()
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finish(if: id) }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finish(if: id) }
    }
}
