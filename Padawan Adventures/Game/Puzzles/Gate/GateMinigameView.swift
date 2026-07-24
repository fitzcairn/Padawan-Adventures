import Combine
import SpriteKit
import SwiftUI
import UIKit

struct GateMinigameView: View {
    let puzzleConfig: GatePuzzleConfig
    let playerFx: SoundEffectTable
    let hudConfig: HudConfig
    let onFinished: (GateOutcome) -> Void

    @StateObject private var session: GateSessionController

    init(
        puzzleConfig: GatePuzzleConfig,
        playerFx: SoundEffectTable,
        hudConfig: HudConfig,
        onFinished: @escaping (GateOutcome) -> Void
    ) {
        self.puzzleConfig = puzzleConfig
        self.playerFx = playerFx
        self.hudConfig = hudConfig
        self.onFinished = onFinished
        _session = StateObject(
            wrappedValue: GateSessionController(
                puzzleConfig: puzzleConfig,
                playerFx: playerFx,
                hudConfig: hudConfig,
                initialTimerSeconds: Int(ceil(puzzleConfig.timerSeconds))
            )
        )
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()

                if let scene = session.scene {
                    GateSpriteView(scene: scene)
                        .ignoresSafeArea()
                }

                GateHUDRepresentable(
                    config: hudConfig,
                    word: session.targetWord,
                    connectedCount: session.connectedCount,
                    timerSeconds: session.timerSeconds,
                    timerUrgent: session.timerUrgent
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .allowsHitTesting(false)

                if session.showUnlocked {
                    GateResultOverlay(kind: .unlocked(starsAwarded: session.starsAwarded)) {
                        session.confirmUnlocked(onFinished: onFinished)
                    }
                }

                if session.showTimesUp {
                    GateResultOverlay(kind: .timesUp) {
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
        .accessibilityIdentifier("minigame.gate")
    }
}

@MainActor
final class GateSessionController: ObservableObject, GateSceneDelegate {
    @Published var timerSeconds: Int
    @Published var timerUrgent = false
    @Published var showUnlocked = false
    @Published var showTimesUp = false
    @Published private(set) var starsAwarded = 0
    @Published private(set) var targetWord = ""
    @Published private(set) var connectedCount = 0
    @Published private(set) var scene: GateScene?

    private let puzzleConfig: GatePuzzleConfig
    private let playerFx: SoundEffectTable
    private let hudConfig: HudConfig
    private var didFinish = false

    init(
        puzzleConfig: GatePuzzleConfig,
        playerFx: SoundEffectTable,
        hudConfig: HudConfig,
        initialTimerSeconds: Int
    ) {
        self.puzzleConfig = puzzleConfig
        self.playerFx = playerFx
        self.hudConfig = hudConfig
        self.timerSeconds = initialTimerSeconds
    }

    func ensureScene(size: CGSize) {
        guard scene == nil else {
            updateSceneSizeIfNeeded(size)
            return
        }
        let safeSize = Self.sanitizedSize(size)
        let created = GateScene(
            size: safeSize,
            puzzleConfig: puzzleConfig,
            playerFx: playerFx
        )
        created.gateDelegate = self
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

    func confirmTimesUp(onFinished: (GateOutcome) -> Void) {
        guard !didFinish else { return }
        didFinish = true
        onFinished(.lost)
    }

    func gateSceneDidUpdateTimer(seconds: Int, urgent: Bool) {
        guard seconds != timerSeconds || urgent != timerUrgent else { return }
        Task { @MainActor in
            self.timerSeconds = seconds
            self.timerUrgent = urgent
        }
    }

    func gateSceneDidSelectWord(_ word: String) {
        Task { @MainActor in
            self.targetWord = word
            self.connectedCount = 0
        }
    }

    func gateSceneDidUpdateConnectedPrefix(_ prefix: String) {
        Task { @MainActor in
            self.connectedCount = prefix.count
        }
    }

    func gateSceneDidWin(starsAwarded: Int) {
        Task { @MainActor in
            self.starsAwarded = starsAwarded
            self.showUnlocked = true
        }
    }

    func gateSceneDidLose() {
        Task { @MainActor in
            self.showTimesUp = true
        }
    }
}

private struct GateSpriteView: UIViewRepresentable {
    let scene: GateScene

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

private struct GateHUDRepresentable: UIViewRepresentable {
    let config: HudConfig
    let word: String
    let connectedCount: Int
    let timerSeconds: Int
    let timerUrgent: Bool

    final class Coordinator {
        var hud: GateHUDView?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        container.isUserInteractionEnabled = false

        let hud = GateHUDView(
            config: config,
            timerSeconds: timerSeconds,
            word: word,
            connectedCount: connectedCount
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
        context.coordinator.hud?.setWord(word, connectedCount: connectedCount)
        context.coordinator.hud?.setTimer(seconds: timerSeconds, urgent: timerUrgent)
    }
}
