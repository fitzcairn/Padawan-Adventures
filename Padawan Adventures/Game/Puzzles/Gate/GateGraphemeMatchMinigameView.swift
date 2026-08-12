import Combine
import SpriteKit
import SwiftUI
import UIKit

struct GateGraphemeMatchMinigameView: View {
    let puzzleConfig: GateGraphemeMatchConfig
    let vocabularySampler: LevelVocabularySampler?
    let onFinished: (MinigameOutcome) -> Void

    @StateObject private var session: GateGraphemeMatchSessionController

    init(
        puzzleConfig: GateGraphemeMatchConfig,
        vocabularySampler: LevelVocabularySampler? = nil,
        onFinished: @escaping (MinigameOutcome) -> Void
    ) {
        self.puzzleConfig = puzzleConfig
        self.vocabularySampler = vocabularySampler
        self.onFinished = onFinished
        _session = StateObject(
            wrappedValue: GateGraphemeMatchSessionController(
                puzzleConfig: puzzleConfig,
                vocabularySampler: vocabularySampler
            )
        )
    }

    var body: some View {
        MinigameShellView(
            scene: session.scene,
            accessibilityRootID: "minigame.gate.grapheme_match",
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
final class GateGraphemeMatchSessionController: ObservableObject, GateGraphemeMatchSceneDelegate {
    @Published var showUnlocked = false
    @Published private(set) var starsAwarded = 0
    @Published private(set) var scene: GateGraphemeMatchScene?

    private let puzzleConfig: GateGraphemeMatchConfig
    private let vocabularySampler: LevelVocabularySampler?
    private var didFinish = false
    private lazy var sceneHost = MinigameSceneHost<GateGraphemeMatchScene>(
        make: { [puzzleConfig, vocabularySampler] size in
            GateGraphemeMatchScene(
                size: size,
                puzzleConfig: puzzleConfig,
                vocabularySampler: vocabularySampler
            )
        },
        onReady: { [weak self] created in
            guard let self else { return }
            created.graphemeMatchDelegate = self
            self.scene = created
        }
    )

    init(
        puzzleConfig: GateGraphemeMatchConfig,
        vocabularySampler: LevelVocabularySampler? = nil
    ) {
        self.puzzleConfig = puzzleConfig
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

    func gateGraphemeMatchSceneDidWin(starsAwarded: Int) {
        self.starsAwarded = starsAwarded
        showUnlocked = true
    }
}
