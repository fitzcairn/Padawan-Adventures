import Combine
import SpriteKit
import SwiftUI
import UIKit

struct PitMinigameView: View {
    let puzzleConfig: PitPuzzleConfig
    let playerFx: SoundEffectTable
    let hudConfig: HudConfig
    let onFinished: (PitOutcome) -> Void

    @StateObject private var session: PitSessionController

    init(
        puzzleConfig: PitPuzzleConfig,
        playerFx: SoundEffectTable,
        hudConfig: HudConfig,
        onFinished: @escaping (PitOutcome) -> Void
    ) {
        self.puzzleConfig = puzzleConfig
        self.playerFx = playerFx
        self.hudConfig = hudConfig
        self.onFinished = onFinished
        _session = StateObject(
            wrappedValue: PitSessionController(
                puzzleConfig: puzzleConfig,
                playerFx: playerFx,
                initialTimerSeconds: Int(ceil(puzzleConfig.timerSeconds))
            )
        )
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()

                if let scene = session.scene {
                    PitSpriteView(scene: scene)
                        .ignoresSafeArea()
                }

                PitHUDRepresentable(
                    config: hudConfig,
                    word: session.targetWord,
                    solvedCount: session.solvedCount,
                    timerSeconds: session.timerSeconds,
                    timerUrgent: session.timerUrgent
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .allowsHitTesting(false)

                if session.showEscaped {
                    PitResultOverlay(
                        kind: .escaped(word: session.targetWord, starsAwarded: session.starsAwarded)
                    ) {
                        session.confirmEscaped(onFinished: onFinished)
                    }
                }

                if session.showFalling {
                    PitResultOverlay(kind: .falling) {
                        session.confirmFalling(onFinished: onFinished)
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
        .accessibilityIdentifier("minigame.pit")
    }
}

@MainActor
final class PitSessionController: ObservableObject, PitSceneDelegate {
    @Published var timerSeconds: Int
    @Published var timerUrgent = false
    @Published var showEscaped = false
    @Published var showFalling = false
    @Published private(set) var starsAwarded = 0
    @Published private(set) var targetWord = ""
    @Published private(set) var solvedCount = 0
    @Published private(set) var scene: PitScene?

    private let puzzleConfig: PitPuzzleConfig
    private let playerFx: SoundEffectTable
    private var didFinish = false

    init(puzzleConfig: PitPuzzleConfig, playerFx: SoundEffectTable, initialTimerSeconds: Int) {
        self.puzzleConfig = puzzleConfig
        self.playerFx = playerFx
        self.timerSeconds = initialTimerSeconds
    }

    func ensureScene(size: CGSize) {
        guard scene == nil else {
            updateSceneSizeIfNeeded(size)
            return
        }
        let safeSize = Self.sanitizedSize(size)
        let created = PitScene(size: safeSize, puzzleConfig: puzzleConfig, playerFx: playerFx)
        created.pitDelegate = self
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

    func confirmEscaped(onFinished: (PitOutcome) -> Void) {
        guard !didFinish else { return }
        didFinish = true
        onFinished(.won(starsAwarded: starsAwarded))
    }

    func confirmFalling(onFinished: (PitOutcome) -> Void) {
        guard !didFinish else { return }
        didFinish = true
        onFinished(.lost)
    }

    func pitSceneDidUpdateTimer(seconds: Int, urgent: Bool) {
        guard seconds != timerSeconds || urgent != timerUrgent else { return }
        Task { @MainActor in
            self.timerSeconds = seconds
            self.timerUrgent = urgent
        }
    }

    func pitSceneDidSelectWord(_ word: String) {
        Task { @MainActor in
            self.targetWord = word
            self.solvedCount = 0
        }
    }

    func pitSceneDidUpdateSolvedCount(_ count: Int) {
        Task { @MainActor in
            self.solvedCount = count
        }
    }

    func pitSceneDidWin(word: String, starsAwarded: Int) {
        Task { @MainActor in
            self.targetWord = word
            self.starsAwarded = starsAwarded
            self.showEscaped = true
        }
    }

    func pitSceneDidLose() {
        Task { @MainActor in
            self.showFalling = true
        }
    }
}

private struct PitSpriteView: UIViewRepresentable {
    let scene: PitScene

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

private struct PitHUDRepresentable: UIViewRepresentable {
    let config: HudConfig
    let word: String
    let solvedCount: Int
    let timerSeconds: Int
    let timerUrgent: Bool

    final class Coordinator {
        var hud: PitHUDView?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        container.isUserInteractionEnabled = false

        let hud = PitHUDView(
            config: config,
            timerSeconds: timerSeconds,
            word: word,
            solvedCount: solvedCount
        )
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
        context.coordinator.hud?.setWord(word, solvedCount: solvedCount)
        context.coordinator.hud?.setTimer(seconds: timerSeconds, urgent: timerUrgent)
    }
}
