import AVFoundation
import Foundation

/// Speaks a queue of phrases via system TTS (placeholder until recorded VO).
/// Used by the pit bridge minigame for letter-tile name cues while dragging.
@MainActor
final class PhonicsSpeaker: NSObject {
    /// Gap after each phrase so a repeated letter reads as separate sounds.
    static let phraseGapSeconds: TimeInterval = 0.35

    private let synthesizer = AVSpeechSynthesizer()
    private var pendingCount = 0
    private var completion: (() -> Void)?
    private let speechDuck = SpeechCueCoordinator()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speaks the queued strings in order, ducking music for the whole utterance run.
    func speak(_ phrases: [String], completion: @escaping () -> Void) {
        cancel()

        let trimmed = phrases
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let volume = SoundEffectsController.shared.soundEffectsVolume
        guard !trimmed.isEmpty, volume > 0 else {
            completion()
            return
        }

        self.completion = completion
        pendingCount = trimmed.count
        startDuckRefresh()

        for phrase in trimmed {
            let utterance = AVSpeechUtterance(string: phrase)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
            utterance.volume = volume
            utterance.postUtteranceDelay = Self.phraseGapSeconds
            synthesizer.speak(utterance)
        }
    }

    /// Stops any in-flight run without calling the stored completion.
    func cancel() {
        synthesizer.stopSpeaking(at: .immediate)
        completion = nil
        pendingCount = 0
        stopDuckRefresh()
    }

    private func startDuckRefresh() {
        speechDuck.startRefreshing(with: SpeechCueCoordinator.DuckPolicy(
            holdDuration: 0.8,
            rearmInterval: 0.4,
            applyHold: { BackgroundMusicController.shared.duckForPhoneticCue(duration: $0) }
        ))
    }

    private func stopDuckRefresh() {
        speechDuck.stop()
    }

    private func finishRun(callCompletion: Bool) {
        stopDuckRefresh()
        let done = completion
        completion = nil
        pendingCount = 0
        if callCompletion {
            done?()
        }
    }
}

extension PhonicsSpeaker: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            guard pendingCount > 0 else { return }
            pendingCount -= 1
            if pendingCount == 0 {
                finishRun(callCompletion: true)
            }
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            finishRun(callCompletion: false)
        }
    }
}
