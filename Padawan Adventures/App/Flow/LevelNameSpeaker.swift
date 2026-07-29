import AVFoundation
import Foundation

/// Speaks a level display name via system TTS (placeholder until recorded VO).
@MainActor
final class LevelNameSpeaker {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let volume = SoundEffectsController.shared.soundEffectsVolume
        guard volume > 0 else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = volume
        synthesizer.speak(utterance)
    }
}
