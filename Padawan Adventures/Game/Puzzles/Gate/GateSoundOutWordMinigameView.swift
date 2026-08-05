import Combine
import SpriteKit
import SwiftUI

/// Host for the sound-out-word gate. The word and its picture are drawn inside the scene
/// (both are tappable), so this shell carries no HUD layer of its own.
struct GateSoundOutWordMinigameView: View {
    let puzzleConfig: GateSoundOutWordConfig
    let hudConfig: HudConfig
    let onFinished: (MinigameOutcome) -> Void

    @StateObject private var session: GateSoundOutWordSessionController

    init(
        puzzleConfig: GateSoundOutWordConfig,
        hudConfig: HudConfig,
        onFinished: @escaping (MinigameOutcome) -> Void
    ) {
        self.puzzleConfig = puzzleConfig
        self.hudConfig = hudConfig
        self.onFinished = onFinished
        _session = StateObject(
            wrappedValue: GateSoundOutWordSessionController(puzzleConfig: puzzleConfig)
        )
    }

    var body: some View {
        MinigameShellView(
            scene: session.scene,
            accessibilityRootID: "minigame.gate",
            ensureScene: session.ensureScene(size:),
            updateSceneSize: session.updateSceneSizeIfNeeded(_:),
            includesHUDLayer: false,
            onLeave: session.showUnlocked ? nil : { session.confirmLeave(onFinished: onFinished) },
            hud: { EmptyView() },
            overlay: {
                if session.showUnlocked {
                    MinigameResultOverlay(starsAwarded: session.starsAwarded) {
                        session.confirmUnlocked(onFinished: onFinished)
                    }
                }
            }
        )
    }
}

@MainActor
final class GateSoundOutWordSessionController: ObservableObject, GateSoundOutWordSceneDelegate {
    @Published var showUnlocked = false
    @Published private(set) var starsAwarded = 0
    @Published private(set) var scene: GateSoundOutWordScene?

    private let puzzleConfig: GateSoundOutWordConfig
    private var didFinish = false
    private lazy var sceneHost = MinigameSceneHost<GateSoundOutWordScene>(
        make: { [puzzleConfig] size in
            GateSoundOutWordScene(size: size, puzzleConfig: puzzleConfig)
        },
        onReady: { [weak self] created in
            guard let self else { return }
            created.soundOutWordDelegate = self
            self.scene = created
        }
    )

    init(puzzleConfig: GateSoundOutWordConfig) {
        self.puzzleConfig = puzzleConfig
    }

    func ensureScene(size: CGSize) {
        sceneHost.ensureScene(size: size)
    }

    func updateSceneSizeIfNeeded(_ size: CGSize) {
        sceneHost.updateSceneSizeIfNeeded(size)
    }

    func confirmUnlocked(onFinished: (MinigameOutcome) -> Void) {
        guard !didFinish else { return }
        didFinish = true
        onFinished(.won(starsAwarded: starsAwarded))
    }

    func confirmLeave(onFinished: (MinigameOutcome) -> Void) {
        guard !didFinish else { return }
        didFinish = true
        onFinished(.abandoned)
    }

    func gateSoundOutWordSceneDidWin(starsAwarded: Int) {
        self.starsAwarded = starsAwarded
        showUnlocked = true
    }
}
