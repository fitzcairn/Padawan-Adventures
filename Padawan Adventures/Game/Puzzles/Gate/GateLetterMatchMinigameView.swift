import Combine
import SpriteKit
import SwiftUI
import UIKit

struct GateLetterMatchMinigameView: View {
    let puzzleConfig: GateLetterMatchConfig
    let playerFx: SoundEffectTable
    let hudConfig: HudConfig
    let onFinished: (MinigameOutcome) -> Void

    @StateObject private var session: GateLetterMatchSessionController

    init(
        puzzleConfig: GateLetterMatchConfig,
        playerFx: SoundEffectTable,
        hudConfig: HudConfig,
        onFinished: @escaping (MinigameOutcome) -> Void
    ) {
        self.puzzleConfig = puzzleConfig
        self.playerFx = playerFx
        self.hudConfig = hudConfig
        self.onFinished = onFinished
        _session = StateObject(
            wrappedValue: GateLetterMatchSessionController(
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
        .accessibilityIdentifier("minigame.gate.letter_match")
    }
}

@MainActor
final class GateLetterMatchSessionController: ObservableObject, GateLetterMatchSceneDelegate {
    @Published var showUnlocked = false
    @Published private(set) var starsAwarded = 0
    @Published private(set) var scene: GateLetterMatchScene?

    private let puzzleConfig: GateLetterMatchConfig
    private let playerFx: SoundEffectTable
    private var didFinish = false
    private lazy var sceneHost = MinigameSceneHost<GateLetterMatchScene>(
        make: { [puzzleConfig, playerFx] size in
            GateLetterMatchScene(
                size: size,
                puzzleConfig: puzzleConfig,
                playerFx: playerFx
            )
        },
        onReady: { [weak self] created in
            guard let self else { return }
            created.letterMatchDelegate = self
            self.scene = created
        }
    )

    init(
        puzzleConfig: GateLetterMatchConfig,
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

    func gateLetterMatchSceneDidWin(starsAwarded: Int) {
        self.starsAwarded = starsAwarded
        showUnlocked = true
    }
}
