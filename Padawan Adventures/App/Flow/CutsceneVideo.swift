import AVFoundation

/// Session-scoped cutscene movie, built during bootstrap so the view can start
/// playback immediately instead of opening a cold file on screen.
@MainActor
final class CutsceneVideo {
    static let basename = "cutscene"
    static let subdirectory = "Backgrounds"

    private let bundle: Bundle
    private(set) var player: AVPlayer?

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    static func url(bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: basename, withExtension: "mp4", subdirectory: subdirectory)
    }

    /// Builds the player and waits briefly for the asset to become playable.
    func preload() async {
        guard player == nil, let url = Self.url(bundle: bundle) else { return }
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        // Hold the last frame instead of rewinding, so the end cue fires once.
        player.actionAtItemEnd = .pause
        // Local file: start on the first frame rather than buffering ahead.
        player.automaticallyWaitsToMinimizeStalling = false
        self.player = player

        // Bounded so a bad asset can never stall the loading screen.
        for _ in 0..<40 {
            if item.status != .unknown { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// Plays from the top; safe on a second new game in the same session.
    func restart() {
        guard let player else { return }
        player.seek(to: .zero)
        player.play()
    }

    func stop() {
        guard let player else { return }
        player.pause()
        player.seek(to: .zero)
    }
}
