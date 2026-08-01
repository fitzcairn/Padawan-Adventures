import Combine
import SpriteKit
import SwiftUI
import UIKit

struct GateLetterMatchMinigameView: View {
    let puzzleConfig: GateLetterMatchConfig
    let playerFx: SoundEffectTable
    let hudConfig: HudConfig
    let onFinished: (GateOutcome) -> Void

    @StateObject private var session: GateLetterMatchSessionController

    init(
        puzzleConfig: GateLetterMatchConfig,
        playerFx: SoundEffectTable,
        hudConfig: HudConfig,
        onFinished: @escaping (GateOutcome) -> Void
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

    init(
        puzzleConfig: GateLetterMatchConfig,
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
        let created = GateLetterMatchScene(
            size: safeSize,
            puzzleConfig: puzzleConfig,
            playerFx: playerFx
        )
        created.letterMatchDelegate = self
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

    func confirmUnlocked(onFinished: (GateOutcome) -> Void) {
        guard !didFinish else { return }
        didFinish = true
        onFinished(.won(starsAwarded: starsAwarded))
    }

    func gateLetterMatchSceneDidWin(starsAwarded: Int) {
        Task { @MainActor in
            self.starsAwarded = starsAwarded
            self.showUnlocked = true
        }
    }
}
