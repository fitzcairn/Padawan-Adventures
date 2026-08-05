import Combine
import SpriteKit
import SwiftUI
import UIKit

struct PitSoundOutWordMinigameView: View {
    let soundOutConfig: PitSoundOutWordConfig
    let pitFx: SoundEffectTable
    let floorTileSetLibrary: FloorTileSetLibrary
    let isoConfig: IsometricConfig
    let spriteLibrary: SpriteLibrary
    let playerSpriteConfig: SpriteConfig?
    let onFinished: (MinigameOutcome) -> Void

    @StateObject private var session: PitSoundOutWordSessionController

    init(
        soundOutConfig: PitSoundOutWordConfig,
        pitFx: SoundEffectTable,
        floorTileSetLibrary: FloorTileSetLibrary,
        isoConfig: IsometricConfig,
        spriteLibrary: SpriteLibrary,
        playerSpriteConfig: SpriteConfig?,
        onFinished: @escaping (MinigameOutcome) -> Void
    ) {
        self.soundOutConfig = soundOutConfig
        self.pitFx = pitFx
        self.floorTileSetLibrary = floorTileSetLibrary
        self.isoConfig = isoConfig
        self.spriteLibrary = spriteLibrary
        self.playerSpriteConfig = playerSpriteConfig
        self.onFinished = onFinished
        _session = StateObject(
            wrappedValue: PitSoundOutWordSessionController(
                soundOutConfig: soundOutConfig,
                pitFx: pitFx,
                floorTileSetLibrary: floorTileSetLibrary,
                isoConfig: isoConfig,
                spriteLibrary: spriteLibrary,
                playerSpriteConfig: playerSpriteConfig
            )
        )
    }

    var body: some View {
        MinigameShellView(
            scene: session.scene,
            accessibilityRootID: "minigame.pit.sound_out_word",
            ensureScene: session.ensureScene(size:),
            updateSceneSize: session.updateSceneSizeIfNeeded(_:),
            includesHUDLayer: false,
            onLeave: session.showWon ? nil : { session.confirmLeave(onFinished: onFinished) },
            hud: { EmptyView() },
            overlay: {
                if session.showWon {
                    MinigameResultOverlay(
                        kind: .escaped(
                            word: session.targetWord,
                            starsAwarded: session.starsAwarded
                        )
                    ) {
                        session.confirmWon(onFinished: onFinished)
                    }
                }
            }
        )
    }
}

@MainActor
final class PitSoundOutWordSessionController: ObservableObject, PitSoundOutWordSceneDelegate {
    @Published var showWon = false
    @Published private(set) var starsAwarded = 0
    @Published private(set) var targetWord = ""
    @Published private(set) var scene: PitSoundOutWordScene?

    private let soundOutConfig: PitSoundOutWordConfig
    private let pitFx: SoundEffectTable
    private let floorTileSetLibrary: FloorTileSetLibrary
    private let isoConfig: IsometricConfig
    private let spriteLibrary: SpriteLibrary
    private let playerSpriteConfig: SpriteConfig?
    private var didFinish = false
    private lazy var sceneHost = MinigameSceneHost<PitSoundOutWordScene>(
        prepare: { [spriteLibrary, playerSpriteConfig] in
            await MinigamePlayerController.preparePlayerSprites(
                in: spriteLibrary,
                config: playerSpriteConfig
            )
        },
        make: { [soundOutConfig, pitFx, floorTileSetLibrary, isoConfig, spriteLibrary, playerSpriteConfig] size in
            PitSoundOutWordScene(
                size: size,
                soundOutConfig: soundOutConfig,
                pitFx: pitFx,
                floorTileSetLibrary: floorTileSetLibrary,
                isoConfig: isoConfig,
                spriteLibrary: spriteLibrary,
                playerSpriteConfig: playerSpriteConfig
            )
        },
        onReady: { [weak self] created in
            guard let self else { return }
            created.soundOutDelegate = self
            self.scene = created
        }
    )

    init(
        soundOutConfig: PitSoundOutWordConfig,
        pitFx: SoundEffectTable,
        floorTileSetLibrary: FloorTileSetLibrary,
        isoConfig: IsometricConfig,
        spriteLibrary: SpriteLibrary,
        playerSpriteConfig: SpriteConfig?
    ) {
        self.soundOutConfig = soundOutConfig
        self.pitFx = pitFx
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

    func confirmLeave(onFinished: (MinigameOutcome) -> Void) {
        guard !didFinish else { return }
        didFinish = true
        onFinished(.abandoned)
    }

    func pitSoundOutWordSceneDidWin(word: String, starsAwarded: Int) {
        self.targetWord = word
        self.starsAwarded = starsAwarded
        Task { @MainActor in
            self.showWon = true
        }
    }
}
