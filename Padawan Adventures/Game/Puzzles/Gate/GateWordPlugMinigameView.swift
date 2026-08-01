import Combine
import SpriteKit
import SwiftUI
import UIKit

struct GateWordPlugMinigameView: View {
    let puzzleConfig: GateWordPlugConfig
    let playerFx: SoundEffectTable
    let hudConfig: HudConfig
    let onFinished: (MinigameOutcome) -> Void

    @StateObject private var session: GateWordPlugSessionController

    init(
        puzzleConfig: GateWordPlugConfig,
        playerFx: SoundEffectTable,
        hudConfig: HudConfig,
        onFinished: @escaping (MinigameOutcome) -> Void
    ) {
        self.puzzleConfig = puzzleConfig
        self.playerFx = playerFx
        self.hudConfig = hudConfig
        self.onFinished = onFinished
        _session = StateObject(
            wrappedValue: GateWordPlugSessionController(
                puzzleConfig: puzzleConfig,
                playerFx: playerFx
            )
        )
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                OverlayChrome.backgroundColor.ignoresSafeArea()

                if let scene = session.scene {
                    SpriteKitSceneView(scene: scene)
                        .ignoresSafeArea()
                }

                if session.showUnlocked {
                    MinigameResultOverlay(
                        kind: .unlocked(starsAwarded: session.starsAwarded)
                    ) {
                        session.confirmUnlocked(onFinished: onFinished)
                    }
                }
            }
            .onAppear {
                session.ensureScene(size: proxy.size)
            }
            .onChange(of: proxy.size) { _, newSize in
                session.updateSceneSizeIfNeeded(newSize)
            }
        }
        .accessibilityIdentifier("minigame.gate.word_plug")
    }
}

@MainActor
final class GateWordPlugSessionController: ObservableObject, GateWordPlugSceneDelegate {
    @Published var showUnlocked = false
    @Published private(set) var starsAwarded = 0
    @Published private(set) var scene: GateWordPlugScene?

    private let puzzleConfig: GateWordPlugConfig
    private let playerFx: SoundEffectTable
    private var didFinish = false
    private lazy var sceneHost = MinigameSceneHost<GateWordPlugScene>(
        make: { [puzzleConfig, playerFx] size in
            GateWordPlugScene(
                size: size,
                puzzleConfig: puzzleConfig,
                playerFx: playerFx
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
        playerFx: SoundEffectTable
    ) {
        self.puzzleConfig = puzzleConfig
        self.playerFx = playerFx
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

    func gateWordPlugSceneDidWin(starsAwarded: Int) {
        self.starsAwarded = starsAwarded
        showUnlocked = true
    }
}
