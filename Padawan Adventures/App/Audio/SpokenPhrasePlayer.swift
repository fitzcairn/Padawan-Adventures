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
        synthesizer.speak(utterance)
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
        let done = completion
        completion = nil
        done?()
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.finish() }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.finish() }
    }
}
