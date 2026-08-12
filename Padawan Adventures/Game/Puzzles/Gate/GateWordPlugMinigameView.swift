import Combine
import SpriteKit
import SwiftUI
import UIKit

struct GateWordPlugMinigameView: View {
    let puzzleConfig: GateWordPlugConfig
    let playerFx: SoundEffectTable
    let vocabularySampler: LevelVocabularySampler?
    let onFinished: (MinigameOutcome) -> Void

    @StateObject private var session: GateWordPlugSessionController

    init(
        puzzleConfig: GateWordPlugConfig,
        playerFx: SoundEffectTable,
        vocabularySampler: LevelVocabularySampler? = nil,
        onFinished: @escaping (MinigameOutcome) -> Void
    ) {
        self.puzzleConfig = puzzleConfig
        self.playerFx = playerFx
        self.vocabularySampler = vocabularySampler
        self.onFinished = onFinished
        _session = StateObject(
            wrappedValue: GateWordPlugSessionController(
                puzzleConfig: puzzleConfig,
                playerFx: playerFx,
                vocabularySampler: vocabularySampler
            )
        )
    }

    private var rootID: String {
        puzzleConfig.letterPosition == .ending ? "minigame.gate.ending_sound" : "minigame.gate.word_plug"
    }

    var body: some View {
        MinigameShellView(
            scene: session.scene,
            accessibilityRootID: rootID,
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
final class GateWordPlugSessionController: ObservableObject, GateWordPlugSceneDelegate {
    @Published var showUnlocked = false
    @Published private(set) var starsAwarded = 0
    @Published private(set) var scene: GateWordPlugScene?

    private let puzzleConfig: GateWordPlugConfig
    private let playerFx: SoundEffectTable
    private let vocabularySampler: LevelVocabularySampler?
    private var didFinish = false
    private lazy var sceneHost = MinigameSceneHost<GateWordPlugScene>(
        make: { [puzzleConfig, playerFx, vocabularySampler] size in
            GateWordPlugScene(
                size: size,
                puzzleConfig: puzzleConfig,
                playerFx: playerFx,
                vocabularySampler: vocabularySampler
            )
        },
        onReady: { [weak self] created in
            guard let self else { return }
            created.wordPlugDelegate = self
            self.scene = created
        }
    )

    init(
        puzzleConfig: GateWordPlugConfig,
        playerFx: SoundEffectTable,
        vocabularySampler: LevelVocabularySampler? = nil
    ) {
        self.puzzleConfig = puzzleConfig
        self.playerFx = playerFx
        self.vocabularySampler = vocabularySampler
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

    func gateWordPlugSceneDidWin(starsAwarded: Int) {
        self.starsAwarded = starsAwarded
        showUnlocked = true
    }
}
