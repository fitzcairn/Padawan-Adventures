import Combine
import SpriteKit
import SwiftUI
import UIKit

struct GateMinigameView: View {
    let puzzleConfig: GateSpellingConfig
    let hudConfig: HudConfig
    let onFinished: (MinigameOutcome) -> Void

    @StateObject private var session: GateSessionController

    init(
        puzzleConfig: GateSpellingConfig,
        hudConfig: HudConfig,
        onFinished: @escaping (MinigameOutcome) -> Void
    ) {
        self.puzzleConfig = puzzleConfig
        self.hudConfig = hudConfig
        self.onFinished = onFinished
        _session = StateObject(
            wrappedValue: GateSessionController(
                puzzleConfig: puzzleConfig,
                hudConfig: hudConfig
            )
        )
    }

    var body: some View {
        MinigameShellView(
            scene: session.scene,
            accessibilityRootID: "minigame.gate",
            ensureScene: session.ensureScene(size:),
            updateSceneSize: session.updateSceneSizeIfNeeded(_:),
            hud: {
                HUDHostRepresentable(
                    makeHUD: {
                        SpellingProgressHUDView(
                            config: hudConfig,
                            word: session.targetWord,
                            progressCount: session.connectedCount,
                            accessibilityID: "gate.word"
                        )
                    },
                    update: { hud in
                        hud.setWord(session.targetWord, progressCount: session.connectedCount)
                    }
                )
            },
            overlay: {
                if session.showUnlocked {
                    MinigameResultOverlay(kind: .unlocked(starsAwarded: session.starsAwarded)) {
                        session.confirmUnlocked(onFinished: onFinished)
                    }
                }
            }
        )
    }
}

@MainActor
final class GateSessionController: ObservableObject, GateSceneDelegate {
    @Published var showUnlocked = false
    @Published private(set) var starsAwarded = 0
    @Published private(set) var targetWord = ""
    @Published private(set) var connectedCount = 0
    @Published private(set) var scene: GateScene?

    private let puzzleConfig: GateSpellingConfig
    private let hudConfig: HudConfig
    private var didFinish = false
    private lazy var sceneHost = MinigameSceneHost<GateScene>(
        make: { [puzzleConfig] size in
            GateScene(
                size: size,
                puzzleConfig: puzzleConfig
            )
        },
        onReady: { [weak self] created in
            guard let self else { return }
            created.gateDelegate = self
            self.scene = created
        }
    )

    init(
        puzzleConfig: GateSpellingConfig,
        hudConfig: HudConfig
    ) {
        self.puzzleConfig = puzzleConfig
        self.hudConfig = hudConfig
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

    func gateSceneDidSelectWord(_ word: String) {
        targetWord = word
        connectedCount = 0
    }

    func gateSceneDidUpdateConnectedPrefix(_ prefix: String) {
        connectedCount = prefix.count
    }

    func gateSceneDidWin(starsAwarded: Int) {
        self.starsAwarded = starsAwarded
        showUnlocked = true
    }
}
