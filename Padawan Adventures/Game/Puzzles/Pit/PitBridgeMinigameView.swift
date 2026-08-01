import Combine
import SpriteKit
import SwiftUI
import UIKit

struct PitBridgeMinigameView: View {
    let bridgeConfig: PitBridgeConfig
    let pitFx: SoundEffectTable
    let playerFx: SoundEffectTable
    let hudConfig: HudConfig
    let floorTileSetLibrary: FloorTileSetLibrary
    let isoConfig: IsometricConfig
    let spriteLibrary: SpriteLibrary
    let playerSpriteConfig: SpriteConfig?
    let onFinished: (MinigameOutcome) -> Void

    @StateObject private var session: PitBridgeSessionController

    init(
        bridgeConfig: PitBridgeConfig,
        pitFx: SoundEffectTable,
        playerFx: SoundEffectTable,
        hudConfig: HudConfig,
        floorTileSetLibrary: FloorTileSetLibrary,
        isoConfig: IsometricConfig,
        spriteLibrary: SpriteLibrary,
        playerSpriteConfig: SpriteConfig?,
        onFinished: @escaping (MinigameOutcome) -> Void
    ) {
        self.bridgeConfig = bridgeConfig
        self.pitFx = pitFx
        self.playerFx = playerFx
        self.hudConfig = hudConfig
        self.floorTileSetLibrary = floorTileSetLibrary
        self.isoConfig = isoConfig
        self.spriteLibrary = spriteLibrary
        self.playerSpriteConfig = playerSpriteConfig
        self.onFinished = onFinished
        _session = StateObject(
            wrappedValue: PitBridgeSessionController(
                bridgeConfig: bridgeConfig,
                pitFx: pitFx,
                playerFx: playerFx,
                floorTileSetLibrary: floorTileSetLibrary,
                isoConfig: isoConfig,
                spriteLibrary: spriteLibrary,
                playerSpriteConfig: playerSpriteConfig
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

                HUDHostRepresentable(
                    makeHUD: {
                        SpellingProgressHUDView(
                            config: hudConfig,
                            word: session.word,
                            progressCount: 0,
                            accessibilityID: "pit.word"
                        )
                    },
                    update: { hud in
                        hud.setWord(session.word, progressCount: 0)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .allowsHitTesting(false)

                if session.showWon {
                    MinigameResultOverlay(
                        kind: .bridged(starsAwarded: session.starsAwarded)
                    ) {
                        session.confirmWon(onFinished: onFinished)
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
        .accessibilityIdentifier("minigame.pit_bridge")
    }
}

@MainActor
final class PitBridgeSessionController: ObservableObject, PitBridgeSceneDelegate {
    @Published var showWon = false
    @Published private(set) var starsAwarded = 0
    @Published private(set) var word = ""
    @Published private(set) var scene: PitBridgeScene?

    private let bridgeConfig: PitBridgeConfig
    private let pitFx: SoundEffectTable
    private let playerFx: SoundEffectTable
    private let floorTileSetLibrary: FloorTileSetLibrary
    private let isoConfig: IsometricConfig
    private let spriteLibrary: SpriteLibrary
    private let playerSpriteConfig: SpriteConfig?
    private var didFinish = false
    private var isCreatingScene = false
    private var pendingSceneSize: CGSize?

    init(
        bridgeConfig: PitBridgeConfig,
        pitFx: SoundEffectTable,
        playerFx: SoundEffectTable,
        floorTileSetLibrary: FloorTileSetLibrary,
        isoConfig: IsometricConfig,
        spriteLibrary: SpriteLibrary,
        playerSpriteConfig: SpriteConfig?
    ) {
        self.bridgeConfig = bridgeConfig
        self.pitFx = pitFx
        self.playerFx = playerFx
        self.floorTileSetLibrary = floorTileSetLibrary
        self.isoConfig = isoConfig
        self.spriteLibrary = spriteLibrary
        self.playerSpriteConfig = playerSpriteConfig
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
        Task {
            if let config = playerSpriteConfig {
                let missingNewClip =
                    spriteLibrary.animation(id: "player", named: "jump_right") == nil
                    || spriteLibrary.animation(id: "player", named: "celebrate_down") == nil
                if missingNewClip,
                   spriteLibrary.animation(id: "player", named: "idle_right") != nil {
                    spriteLibrary.invalidate(id: "player")
                }
                await spriteLibrary.ensureLoaded(config, id: "player")
            }
            let finalSize = pendingSceneSize ?? safeSize
            let created = PitBridgeScene(
                size: finalSize,
                bridgeConfig: bridgeConfig,
                pitFx: pitFx,
                playerFx: playerFx,
                floorTileSetLibrary: floorTileSetLibrary,
                isoConfig: isoConfig,
                spriteLibrary: spriteLibrary,
                playerSpriteConfig: playerSpriteConfig
            )
            created.bridgeDelegate = self
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

    func confirmWon(onFinished: (MinigameOutcome) -> Void) {
        guard !didFinish else { return }
        didFinish = true
        onFinished(.won(starsAwarded: starsAwarded))
    }

    func pitBridgeSceneDidUpdateWord(_ word: String) {
        Task { @MainActor in
            self.word = word
        }
    }

    func pitBridgeSceneDidWin(starsAwarded: Int) {
        Task { @MainActor in
            self.starsAwarded = starsAwarded
            self.showWon = true
        }
    }
}
