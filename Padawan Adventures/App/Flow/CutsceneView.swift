import AVFoundation
import SwiftUI

/// Story beat between NEW GAME and the planet map: the cutscene movie with the
/// player idle on the left and Yoda talking back at him from the right.
struct CutsceneView: View {
    let session: AppSession
    let router: FlowRouter

    @State private var playerFrames: [(image: UIImage, duration: TimeInterval)] = []
    @State private var yodaFrames: [(image: UIImage, duration: TimeInterval)] = []
    @State private var didFinish = false

    private static let playerHeight: CGFloat = 200
    private static let yodaHeight: CGFloat = 170

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player = session.cutsceneVideo.player {
                CutsceneVideoLayerView(player: player)
                    .ignoresSafeArea()
                    .onReceive(
                        NotificationCenter.default.publisher(
                            for: AVPlayerItem.didPlayToEndTimeNotification,
                            object: player.currentItem
                        )
                    ) { _ in
                        finish(fadeAudio: false)
                    }
            }

            HStack(alignment: .bottom) {
                AnimatedUIImageView(frames: playerFrames)
                    .frame(height: Self.playerHeight)
                Spacer(minLength: 0)
                AnimatedUIImageView(frames: yodaFrames)
                    .frame(height: Self.yodaHeight)
                    // Sheet faces southeast; mirror it so he faces the player.
                    .scaleEffect(x: -1, y: 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

            AppTitleText(text: "Tap to Skip", size: 15, weight: .regular)
                .accessibilityIdentifier("cutscene.skip")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { finish(fadeAudio: true) }
        .playScreenMusic("cutscene")
        .task {
            GameLogger.mark(
                .flow,
                "cutscene appeared (video=\(session.cutsceneVideo.player != nil))"
            )
            session.cutsceneVideo.restart()
            await GameLogger.step(.flow, "cutscene.loadCharacters") {
                await loadCharacters()
            }
        }
        .onDisappear {
            GameLogger.mark(.flow, "cutscene disappeared")
            // Skip owns teardown via fadeOutAndStop; don't hard-cut mid-fade.
            if !session.cutsceneVideo.isFadingOut {
                session.cutsceneVideo.stop()
            }
        }
    }

    private func finish(fadeAudio: Bool) {
        // The skip tap and the end-of-movie cue can race; only the first wins.
        guard !didFinish else { return }
        didFinish = true
        GameLogger.mark(.flow, "cutscene finish (fadeAudio: \(fadeAudio))")
        // Navigate immediately so the view crossfade starts with the audio fade.
        router.showLevelSelect()
        if fadeAudio {
            Task {
                await session.cutsceneVideo.fadeOutAndStop()
            }
        } else {
            session.cutsceneVideo.stop()
        }
    }

    private func loadCharacters() async {
        guard let config = try? CutsceneSpritesConfig.loadFromBundle() else { return }
        for entry in config.entries {
            await session.spriteLibrary.ensureLoaded(entry.config, id: entry.id)
            let frames = session.spriteLibrary.uiImages(id: entry.id) ?? []
            switch entry.id {
            case CutsceneSpritesConfig.playerID:
                playerFrames = frames
            case CutsceneSpritesConfig.yodaID:
                yodaFrames = frames
            default:
                break
            }
        }
    }
}

/// Centers the movie and matches its largest dimension to the view.
///
/// `layerClass` hands layout to UIKit, so the layer tracks the view on rotation
/// without any manual frame math.
private struct CutsceneVideoLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.backgroundColor = .black
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ view: PlayerLayerView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
    }

    final class PlayerLayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }

        /// `layerClass` guarantees the type; log before trapping so a broken
        /// invariant is identifiable from the console rather than a bare cast.
        var playerLayer: AVPlayerLayer {
            guard let playerLayer = layer as? AVPlayerLayer else {
                GameLogger.fault(
                    .flow,
                    "cutscene layer is \(type(of: layer)), expected AVPlayerLayer"
                )
                GameLogger.dumpBreadcrumbs()
                preconditionFailure("Cutscene layer is not an AVPlayerLayer")
            }
            return playerLayer
        }
    }
}
