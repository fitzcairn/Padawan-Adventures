import Combine
import SpriteKit
import SwiftUI
import UIKit

struct PitMinigameView: View {
    let puzzleConfig: PitPuzzleConfig
    let playerFx: SoundEffectTable
    let hudConfig: HudConfig
    let pitSpriteSetLibrary: PitSpriteSetLibrary
    let floorTileSetLibrary: FloorTileSetLibrary
    let isoConfig: IsometricConfig
    let spriteLibrary: SpriteLibrary
    let playerSpriteConfig: SpriteConfig?
    let onFinished: (PitOutcome) -> Void

    @StateObject private var session: PitSessionController

    init(
        puzzleConfig: PitPuzzleConfig,
        playerFx: SoundEffectTable,
        hudConfig: HudConfig,
        pitSpriteSetLibrary: PitSpriteSetLibrary,
        floorTileSetLibrary: FloorTileSetLibrary,
        isoConfig: IsometricConfig,
        spriteLibrary: SpriteLibrary,
        playerSpriteConfig: SpriteConfig?,
        onFinished: @escaping (PitOutcome) -> Void
    ) {
        self.puzzleConfig = puzzleConfig
        self.playerFx = playerFx
        self.hudConfig = hudConfig
        self.pitSpriteSetLibrary = pitSpriteSetLibrary
        self.floorTileSetLibrary = floorTileSetLibrary
        self.isoConfig = isoConfig
        self.spriteLibrary = spriteLibrary
        self.playerSpriteConfig = playerSpriteConfig
        self.onFinished = onFinished
        _session = StateObject(
            wrappedValue: PitSessionController(
                puzzleConfig: puzzleConfig,
                playerFx: playerFx,
                pitSpriteSetLibrary: pitSpriteSetLibrary,
                floorTileSetLibrary: floorTileSetLibrary,
                isoConfig: isoConfig,
                spriteLibrary: spriteLibrary,
                playerSpriteConfig: playerSpriteConfig,
                initialTimerSeconds: Int(ceil(puzzleConfig.timerSeconds))
            )
        )
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                OverlayChrome.backgroundColor.ignoresSafeArea()

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
    private let pitSpriteSetLibrary: PitSpriteSetLibrary
    private let floorTileSetLibrary: FloorTileSetLibrary
    private let isoConfig: IsometricConfig
    private let spriteLibrary: SpriteLibrary
    private let playerSpriteConfig: SpriteConfig?
    private var didFinish = false
    private var isCreatingScene = false
    private var pendingSceneSize: CGSize?

    init(
        puzzleConfig: PitPuzzleConfig,
        playerFx: SoundEffectTable,
        pitSpriteSetLibrary: PitSpriteSetLibrary,
        floorTileSetLibrary: FloorTileSetLibrary,
        isoConfig: IsometricConfig,
        spriteLibrary: SpriteLibrary,
        playerSpriteConfig: SpriteConfig?,
        initialTimerSeconds: Int
    ) {
        self.puzzleConfig = puzzleConfig
        self.playerFx = playerFx
        self.pitSpriteSetLibrary = pitSpriteSetLibrary
        self.floorTileSetLibrary = floorTileSetLibrary
        self.isoConfig = isoConfig
        self.spriteLibrary = spriteLibrary
        self.playerSpriteConfig = playerSpriteConfig
        self.timerSeconds = initialTimerSeconds
    }

    func ensureScene(size: CGSize) {
        let safeSize = Self.sanitizedSize(size)
        if scene != nil {
            updateSceneSizeIfNeeded(safeSize)
            return
        }
        pendingSceneSize = safeSize
        guard !isCreatingScene else { return }
        isCreatingScene = true
        // Ensure player sheets are loaded (covers cold start / jump clip added mid-session).
        Task {
            if let config = playerSpriteConfig {
                let missingNewClip =
                    spriteLibrary.animation(id: "player", named: "jump_right") == nil
                    || spriteLibrary.animation(id: "player", named: "celebrate_down") == nil
                if missingNewClip,
                   spriteLibrary.animation(id: "player", named: "idle_right") != nil {
                    // Player was loaded before newer clips existed — reload once.
                    spriteLibrary.invalidate(id: "player")
                }
                await spriteLibrary.ensureLoaded(config, id: "player")
            }
            let finalSize = pendingSceneSize ?? safeSize
            let created = PitScene(
                size: finalSize,
                puzzleConfig: puzzleConfig,
                playerFx: playerFx,
                pitSpriteSetLibrary: pitSpriteSetLibrary,
                floorTileSetLibrary: floorTileSetLibrary,
                isoConfig: isoConfig,
                spriteLibrary: spriteLibrary,
                playerSpriteConfig: playerSpriteConfig
            )
            created.pitDelegate = self
            scene = created
            isCreatingScene = false
        }
    }

    func updateSceneSizeIfNeeded(_ size: CGSize) {
        let safeSize = Self.sanitizedSize(size)
        if scene == nil {
            pendingSceneSize = safeSize
            return
        }
        guard let scene else { return }
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
