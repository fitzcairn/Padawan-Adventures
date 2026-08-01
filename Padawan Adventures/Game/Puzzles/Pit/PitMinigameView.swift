import Combine
import SpriteKit
import SwiftUI
import UIKit

struct PitMinigameView: View {
    let puzzleConfig: PitPuzzleConfig
    let pitFx: SoundEffectTable
    let playerFx: SoundEffectTable
    let hudConfig: HudConfig
    let pitSpriteSetLibrary: PitSpriteSetLibrary
    let floorTileSetLibrary: FloorTileSetLibrary
    let isoConfig: IsometricConfig
    let spriteLibrary: SpriteLibrary
    let playerSpriteConfig: SpriteConfig?
    let onFinished: (MinigameOutcome) -> Void

    @StateObject private var session: PitSessionController

    init(
        puzzleConfig: PitPuzzleConfig,
        pitFx: SoundEffectTable,
        playerFx: SoundEffectTable,
        hudConfig: HudConfig,
        pitSpriteSetLibrary: PitSpriteSetLibrary,
        floorTileSetLibrary: FloorTileSetLibrary,
        isoConfig: IsometricConfig,
        spriteLibrary: SpriteLibrary,
        playerSpriteConfig: SpriteConfig?,
        onFinished: @escaping (MinigameOutcome) -> Void
    ) {
        self.puzzleConfig = puzzleConfig
        self.pitFx = pitFx
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
                pitFx: pitFx,
                playerFx: playerFx,
                pitSpriteSetLibrary: pitSpriteSetLibrary,
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
                            word: session.targetWord,
                            progressCount: session.solvedCount,
                            accessibilityID: "pit.word"
                        )
                    },
                    update: { hud in
                        hud.setWord(session.targetWord, progressCount: session.solvedCount)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .allowsHitTesting(false)

                if session.showEscaped {
                    MinigameResultOverlay(
                        kind: .escaped(word: session.targetWord, starsAwarded: session.starsAwarded)
                    ) {
                        session.confirmEscaped(onFinished: onFinished)
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
    @Published var showEscaped = false
    @Published private(set) var starsAwarded = 0
    @Published private(set) var targetWord = ""
    @Published private(set) var solvedCount = 0
    @Published private(set) var scene: PitScene?

    private let puzzleConfig: PitPuzzleConfig
    private let pitFx: SoundEffectTable
    private let playerFx: SoundEffectTable
    private let pitSpriteSetLibrary: PitSpriteSetLibrary
    private let floorTileSetLibrary: FloorTileSetLibrary
    private let isoConfig: IsometricConfig
    private let spriteLibrary: SpriteLibrary
    private let playerSpriteConfig: SpriteConfig?
    private var didFinish = false
    private lazy var sceneHost = MinigameSceneHost<PitScene>(
        prepare: { [spriteLibrary, playerSpriteConfig] in
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
        },
        make: { [puzzleConfig, pitFx, playerFx, pitSpriteSetLibrary, floorTileSetLibrary, isoConfig, spriteLibrary, playerSpriteConfig] size in
            PitScene(
                size: size,
                puzzleConfig: puzzleConfig,
                pitFx: pitFx,
                playerFx: playerFx,
                pitSpriteSetLibrary: pitSpriteSetLibrary,
                floorTileSetLibrary: floorTileSetLibrary,
                isoConfig: isoConfig,
                spriteLibrary: spriteLibrary,
                playerSpriteConfig: playerSpriteConfig
            )
        },
        onReady: { [weak self] created in
            guard let self else { return }
            created.pitDelegate = self
            self.scene = created
        }
    )

    init(
        puzzleConfig: PitPuzzleConfig,
        pitFx: SoundEffectTable,
        playerFx: SoundEffectTable,
        pitSpriteSetLibrary: PitSpriteSetLibrary,
        floorTileSetLibrary: FloorTileSetLibrary,
        isoConfig: IsometricConfig,
        spriteLibrary: SpriteLibrary,
        playerSpriteConfig: SpriteConfig?
    ) {
        self.puzzleConfig = puzzleConfig
        self.pitFx = pitFx
        self.playerFx = playerFx
        self.pitSpriteSetLibrary = pitSpriteSetLibrary
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

    func confirmEscaped(onFinished: (MinigameOutcome) -> Void) {
        guard !didFinish else { return }
        didFinish = true
        onFinished(.won(starsAwarded: starsAwarded))
    }

    func pitSceneDidSelectWord(_ word: String) {
        targetWord = word
        solvedCount = 0
    }

    func pitSceneDidUpdateSolvedCount(_ count: Int) {
        solvedCount = count
    }

    func pitSceneDidWin(word: String, starsAwarded: Int) {
        targetWord = word
        self.starsAwarded = starsAwarded
        showEscaped = true
    }
}
