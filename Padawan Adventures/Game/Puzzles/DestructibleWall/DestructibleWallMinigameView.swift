import Combine
import SpriteKit
import SwiftUI
import UIKit

struct DestructibleWallMinigameView: View {
    let puzzleConfig: DestructibleWallPuzzleConfig
    let playerFx: SoundEffectTable
    let hudConfig: HudConfig
    let letterSpriteSetLibrary: LetterSpriteSetLibrary
    let onFinished: (DestructibleWallOutcome) -> Void

    @StateObject private var session: DestructibleWallSessionController

    init(
        puzzleConfig: DestructibleWallPuzzleConfig,
        playerFx: SoundEffectTable,
        hudConfig: HudConfig,
        letterSpriteSetLibrary: LetterSpriteSetLibrary,
        onFinished: @escaping (DestructibleWallOutcome) -> Void
    ) {
        self.puzzleConfig = puzzleConfig
        self.playerFx = playerFx
        self.hudConfig = hudConfig
        self.letterSpriteSetLibrary = letterSpriteSetLibrary
        self.onFinished = onFinished
        _session = StateObject(
            wrappedValue: DestructibleWallSessionController(
                puzzleConfig: puzzleConfig,
                playerFx: playerFx,
                letterSpriteSetLibrary: letterSpriteSetLibrary,
                initialTimerSeconds: Int(ceil(puzzleConfig.timerSeconds))
            )
        )
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()

                if let scene = session.scene {
                    DestructibleWallSpriteView(scene: scene)
                        .ignoresSafeArea()
                }

                DestructibleWallHUDRepresentable(
                    config: hudConfig,
                    timerSeconds: session.timerSeconds,
                    timerUrgent: session.timerUrgent
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .allowsHitTesting(false)

                if session.showDestroyed {
                    DestructibleWallResultOverlay(
                        kind: .destroyed(starsAwarded: session.starsAwarded)
                    ) {
                        session.confirmDestroyed(onFinished: onFinished)
                    }
                }

                if session.showTimesUp {
                    DestructibleWallResultOverlay(kind: .timesUp) {
                        session.confirmTimesUp(onFinished: onFinished)
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
        .accessibilityIdentifier("minigame.destructible_wall")
    }
}

@MainActor
final class DestructibleWallSessionController: ObservableObject, DestructibleWallSceneDelegate {
    @Published var timerSeconds: Int
    @Published var timerUrgent = false
    @Published var showDestroyed = false
    @Published var showTimesUp = false
    @Published private(set) var starsAwarded = 0
    @Published private(set) var scene: DestructibleWallScene?

    private let puzzleConfig: DestructibleWallPuzzleConfig
    private let playerFx: SoundEffectTable
    private let letterSpriteSetLibrary: LetterSpriteSetLibrary
    private var didFinish = false

    init(
        puzzleConfig: DestructibleWallPuzzleConfig,
        playerFx: SoundEffectTable,
        letterSpriteSetLibrary: LetterSpriteSetLibrary,
        initialTimerSeconds: Int
    ) {
        self.puzzleConfig = puzzleConfig
        self.playerFx = playerFx
        self.letterSpriteSetLibrary = letterSpriteSetLibrary
        self.timerSeconds = initialTimerSeconds
    }

    func ensureScene(size: CGSize) {
        guard scene == nil else {
            updateSceneSizeIfNeeded(size)
            return
        }
        let safeSize = Self.sanitizedSize(size)
        let created = DestructibleWallScene(
            size: safeSize,
            puzzleConfig: puzzleConfig,
            playerFx: playerFx,
            letterSpriteSetLibrary: letterSpriteSetLibrary
        )
        created.wallDelegate = self
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

    func confirmDestroyed(onFinished: (DestructibleWallOutcome) -> Void) {
        guard !didFinish else { return }
        didFinish = true
        onFinished(.won(starsAwarded: starsAwarded))
    }

    func confirmTimesUp(onFinished: (DestructibleWallOutcome) -> Void) {
        guard !didFinish else { return }
        didFinish = true
        onFinished(.lost)
    }

    func destructibleWallSceneDidUpdateTimer(seconds: Int, urgent: Bool) {
        guard seconds != timerSeconds || urgent != timerUrgent else { return }
        Task { @MainActor in
            self.timerSeconds = seconds
            self.timerUrgent = urgent
        }
    }

    func destructibleWallSceneDidWin(starsAwarded: Int) {
        Task { @MainActor in
            self.starsAwarded = starsAwarded
            self.showDestroyed = true
        }
    }

    func destructibleWallSceneDidLose() {
        Task { @MainActor in
            self.showTimesUp = true
        }
    }
}

private struct DestructibleWallSpriteView: UIViewRepresentable {
    let scene: DestructibleWallScene

    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        view.allowsTransparency = false
        view.ignoresSiblingOrder = true
        view.presentScene(scene)
        return view
    }

    func updateUIView(_ uiView: SKView, context: Context) {
        if uiView.scene !== scene {
            uiView.presentScene(scene)
        }
    }
}

private struct DestructibleWallHUDRepresentable: UIViewRepresentable {
    let config: HudConfig
    let timerSeconds: Int
    let timerUrgent: Bool

    final class Coordinator {
        var hud: DestructibleWallHUDView?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        container.isUserInteractionEnabled = false

        let hud = DestructibleWallHUDView(config: config, timerSeconds: timerSeconds)
        hud.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hud)
        NSLayoutConstraint.activate([
            hud.topAnchor.constraint(equalTo: container.topAnchor),
            hud.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hud.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hud.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        context.coordinator.hud = hud
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.hud?.setTimer(seconds: timerSeconds, urgent: timerUrgent)
    }
}
