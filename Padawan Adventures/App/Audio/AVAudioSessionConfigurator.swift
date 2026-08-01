import AVFoundation
import Foundation

/// One-shot ambient session setup shared by bundle music and SFX players.
enum AVAudioSessionConfigurator {
    private static var didConfigure = false

    static func configureAmbientIfNeeded() {
        guard !didConfigure else { return }
        didConfigure = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [])
        try? session.setActive(true)
    }
}
