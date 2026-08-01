import Combine
import SpriteKit
import SwiftUI
import UIKit

struct GateLetterMatchMinigameView: View {
    let puzzleConfig: GateLetterMatchConfig
    let onFinished: (MinigameOutcome) -> Void

    @StateObject private var session: GateLetterMatchSessionController

    init(
        puzzleConfig: GateLetterMatchConfig,
        onFinished: @escaping (MinigameOutcome) -> Void
    ) {
        self.puzzleConfig = puzzleConfig
        self.onFinished = onFinished
        _session = StateObject(
            wrappedValue: GateLetterMatchSessionController(
                puzzleConfig: puzzleConfig
            )
        )
    }

    var body: some View {
        MinigameShellView(
            scene: session.scene,
            accessibilityRootID: "minigame.gate.letter_match",
            ensureScene: session.ensureScene(size:),
            updateSceneSize: session.updateSceneSizeIfNeeded(_:),
            includesHUDLayer: false,
            hud: { EmptyView() },
            overlay: {
                if session.showUnlocked {
                    MinigameResultOverlay(
                        kind: .unlocked(starsAwarded: session.starsAwarded)
                    ) {
                        session.confirmUnlocked(onFinished: onFinished)
                    }
                }
            }
        )
    }
}

@MainActor
final class GateLetterMatchSessionController: ObservableObject, GateLetterMatchSceneDelegate {
    @Published var showUnlocked = false
    @Published private(set) var starsAwarded = 0
    @Published private(set) var scene: GateLetterMatchScene?

    private let puzzleConfig: GateLetterMatchConfig
    private var didFinish = false
    private lazy var sceneHost = MinigameSceneHost<GateLetterMatchScene>(
        make: { [puzzleConfig] size in
            GateLetterMatchScene(
                size: size,
                puzzleConfig: puzzleConfig
            )
        },
        onReady: { [weak self] created in
            guard let self else { return }
            created.letterMatchDelegate = self
            self.scene = created
        }
    )

    init(puzzleConfig: GateLetterMatchConfig) {
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

    func gateLetterMatchSceneDidWin(starsAwarded: Int) {
        self.starsAwarded = starsAwarded
        showUnlocked = true
    }
}
