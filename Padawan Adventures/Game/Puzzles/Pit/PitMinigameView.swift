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
    private var isCreatingScene = false
    private var pendingSceneSize: CGSize?

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
                pitFx: pitFx,
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

    func confirmEscaped(onFinished: (MinigameOutcome) -> Void) {
        guard !didFinish else { return }
        didFinish = true
        onFinished(.won(starsAwarded: starsAwarded))
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
}
