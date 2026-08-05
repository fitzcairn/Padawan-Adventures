import Combine
import SpriteKit
import SwiftUI
import UIKit

struct PitBridgeMinigameView: View {
    let bridgeConfig: PitBridgeConfig
    let pitFx: SoundEffectTable
    let playerFx: SoundEffectTable
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
        floorTileSetLibrary: FloorTileSetLibrary,
        isoConfig: IsometricConfig,
        spriteLibrary: SpriteLibrary,
        playerSpriteConfig: SpriteConfig?,
        onFinished: @escaping (MinigameOutcome) -> Void
    ) {
        self.bridgeConfig = bridgeConfig
        self.pitFx = pitFx
        self.playerFx = playerFx
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

    private var rootID: String {
        bridgeConfig.letterPosition == .starting ? "minigame.pit.starting_sound" : "minigame.pit_bridge"
    }

    var body: some View {
        MinigameShellView(
            scene: session.scene,
            accessibilityRootID: rootID,
            ensureScene: session.ensureScene(size:),
            updateSceneSize: session.updateSceneSizeIfNeeded(_:),
            includesHUDLayer: false,
            hud: { EmptyView() },
            overlay: {
                if session.showWon {
                    MinigameResultOverlay(
                        kind: .bridged(starsAwarded: session.starsAwarded)
                    ) {
                        session.confirmWon(onFinished: onFinished)
                    }
                }
            }
        )
    }
}

@MainActor
final class PitBridgeSessionController: ObservableObject, PitBridgeSceneDelegate {
    @Published var showWon = false
    @Published private(set) var starsAwarded = 0
    @Published private(set) var scene: PitBridgeScene?

    private let bridgeConfig: PitBridgeConfig
    private let pitFx: SoundEffectTable
    private let playerFx: SoundEffectTable
    private let floorTileSetLibrary: FloorTileSetLibrary
    private let isoConfig: IsometricConfig
    private let spriteLibrary: SpriteLibrary
    private let playerSpriteConfig: SpriteConfig?
    private var didFinish = false
    private lazy var sceneHost = MinigameSceneHost<PitBridgeScene>(
        prepare: { [spriteLibrary, playerSpriteConfig] in
            await MinigamePlayerController.preparePlayerSprites(
                in: spriteLibrary,
                config: playerSpriteConfig
            )
        },
        make: { [bridgeConfig, pitFx, playerFx, floorTileSetLibrary, isoConfig, spriteLibrary, playerSpriteConfig] size in
            PitBridgeScene(
                size: size,
                bridgeConfig: bridgeConfig,
                pitFx: pitFx,
                playerFx: playerFx,
                floorTileSetLibrary: floorTileSetLibrary,
                isoConfig: isoConfig,
                spriteLibrary: spriteLibrary,
                playerSpriteConfig: playerSpriteConfig
            )
        },
        onReady: { [weak self] created in
            guard let self else { return }
            created.bridgeDelegate = self
            self.scene = created
        }
    )

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
        sceneHost.ensureScene(size: size)
    }

    func updateSceneSizeIfNeeded(_ size: CGSize) {
        sceneHost.updateSceneSizeIfNeeded(size)
    }

    func confirmWon(onFinished: (MinigameOutcome) -> Void) {
        guard !didFinish else { return }
        didFinish = true
        onFinished(.won(starsAwarded: starsAwarded))
    }

    func pitBridgeSceneDidWin(starsAwarded: Int) {
        self.starsAwarded = starsAwarded
        Task { @MainActor in
            self.showWon = true
        }
    }
}
