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
                    GateResultOverlay(
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

    init(
        puzzleConfig: GateWordPlugConfig,
        playerFx: SoundEffectTable
    ) {
        self.puzzleConfig = puzzleConfig
        self.playerFx = playerFx
    }

    func ensureScene(size: CGSize) {
        guard scene == nil else {
            updateSceneSizeIfNeeded(size)
            return
        }
        let safeSize = Self.sanitizedSize(size)
        let created = GateWordPlugScene(
            size: safeSize,
            puzzleConfig: puzzleConfig,
            playerFx: playerFx
        )
        created.wordPlugDelegate = self
        scene = created
    }

    func updateSceneSizeIfNeeded(_ size: CGSize) {
        guard let scene else { return }
        let safeSize = Self.sanitizedSize(size)
        let dw = abs(scene.size.width - safeSize.width)
        let dh = abs(scene.size.height - safeSize.height)
        guard dw > 8 || dh > 8 else { return }
        scene.size = safeSize
    }

    private static func sanitizedSize(_ size: CGSize) -> CGSize {
        CGSize(width: max(size.width, 320), height: max(size.height, 240))
    }

    func confirmUnlocked(onFinished: (MinigameOutcome) -> Void) {
        guard !didFinish else { return }
        didFinish = true
        onFinished(.won(starsAwarded: starsAwarded))
    }

    func gateWordPlugSceneDidWin(starsAwarded: Int) {
        Task { @MainActor in
            self.starsAwarded = starsAwarded
            self.showUnlocked = true
        }
    }
}
