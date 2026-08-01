import Combine
import SpriteKit
import SwiftUI
import UIKit

struct EnemyMinigameView: View {
    let enemyType: EnemyTypeConfig
    let healthCount: Int
    let playerFx: SoundEffectTable
    let hudConfig: HudConfig
    let letterSoundRepeatSeconds: Double
    let letterSpawnRate: Double
    let letterCase: CombatLetterCase
    let slashMaxSeconds: Double
    let slashMaxScreenWidthFraction: Double
    let spriteLibrary: SpriteLibrary
    let letterSpriteSetLibrary: LetterSpriteSetLibrary
    let combatSprite: SpriteConfig?
    let enemySprite: (id: String, config: SpriteConfig)?
    let wallHeight: CGFloat
    let onFinished: (MinigameOutcome) -> Void

    @StateObject private var session: CombatSessionController

    init(
        enemyType: EnemyTypeConfig,
        healthCount: Int,
        playerFx: SoundEffectTable,
        hudConfig: HudConfig,
        letterSoundRepeatSeconds: Double = CombatMinigameEngine.Config.defaultLetterSoundRepeatSeconds,
        letterSpawnRate: Double = CombatMinigameEngine.Config.defaultLetterSpawnRate,
        letterCase: CombatLetterCase = .upper,
        slashMaxSeconds: Double = EnemyConfig.fallbackSlashMaxSeconds,
        slashMaxScreenWidthFraction: Double = EnemyConfig.fallbackSlashMaxScreenWidthFraction,
        spriteLibrary: SpriteLibrary,
        letterSpriteSetLibrary: LetterSpriteSetLibrary,
        combatSprite: SpriteConfig?,
        enemySprite: (id: String, config: SpriteConfig)?,
        wallHeight: CGFloat,
        onFinished: @escaping (MinigameOutcome) -> Void
    ) {
        self.enemyType = enemyType
        self.healthCount = healthCount
        self.playerFx = playerFx
        self.hudConfig = hudConfig
        self.letterSoundRepeatSeconds = letterSoundRepeatSeconds
        self.letterSpawnRate = letterSpawnRate
        self.letterCase = letterCase
        self.slashMaxSeconds = slashMaxSeconds
        self.slashMaxScreenWidthFraction = slashMaxScreenWidthFraction
        self.spriteLibrary = spriteLibrary
        self.letterSpriteSetLibrary = letterSpriteSetLibrary
        self.combatSprite = combatSprite
        self.enemySprite = enemySprite
        self.wallHeight = wallHeight
        self.onFinished = onFinished
        _session = StateObject(
            wrappedValue: CombatSessionController(
                enemyType: enemyType,
                playerFx: playerFx,
                startingHealth: healthCount,
                letterSoundRepeatSeconds: letterSoundRepeatSeconds,
                letterSpawnRate: letterSpawnRate,
                letterCase: letterCase,
                slashMaxSeconds: slashMaxSeconds,
                slashMaxScreenWidthFraction: slashMaxScreenWidthFraction,
                spriteLibrary: spriteLibrary,
                letterSpriteSetLibrary: letterSpriteSetLibrary,
                combatSprite: combatSprite,
                enemySprite: enemySprite,
                wallHeight: wallHeight
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
                        CombatHUDView(
                            config: hudConfig,
                            healthCount: session.health,
                            progress: session.stars,
                            progressGoal: enemyType.starsToWin
                        )
                    },
                    update: { hud in
                        hud.setHealth(session.health)
                        hud.setProgress(current: session.stars, goal: enemyType.starsToWin)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                // HUD must not steal touches from the SpriteKit slash input underneath.
                .allowsHitTesting(false)

                if session.showVictory {
                    CombatVictoryView {
                        session.confirmVictory(onFinished: onFinished)
                    }
                }
            }
            .onAppear {
                session.onLost = { onFinished(.lost) }
                session.ensureScene(size: proxy.size)
            }
            .onChange(of: proxy.size) { _, newSize in
                // Only adopt meaningful size changes; ignore layout jitter.
                session.updateSceneSizeIfNeeded(newSize)
            }
        }
        .accessibilityIdentifier("minigame.enemy")
    }
}

@MainActor
final class CombatSessionController: ObservableObject, CombatSceneDelegate {
    @Published var stars = 0
    @Published var health: Int
    @Published var showVictory = false
    @Published private(set) var scene: CombatScene?

    var onLost: (() -> Void)?

    private let enemyType: EnemyTypeConfig
    private let playerFx: SoundEffectTable
    private let startingHealth: Int
    private let letterSoundRepeatSeconds: Double
    private let letterSpawnRate: Double
    private let letterCase: CombatLetterCase
    private let slashMaxSeconds: Double
    private let slashMaxScreenWidthFraction: Double
    private let spriteLibrary: SpriteLibrary
    private let letterSpriteSetLibrary: LetterSpriteSetLibrary
    private let combatSprite: SpriteConfig?
    private let enemySprite: (id: String, config: SpriteConfig)?
    private let wallHeight: CGFloat
    private var starsAwarded = 0
    private var didFinish = false

    init(
        enemyType: EnemyTypeConfig,
        playerFx: SoundEffectTable,
        startingHealth: Int,
        letterSoundRepeatSeconds: Double = CombatMinigameEngine.Config.defaultLetterSoundRepeatSeconds,
        letterSpawnRate: Double = CombatMinigameEngine.Config.defaultLetterSpawnRate,
        letterCase: CombatLetterCase = .upper,
        slashMaxSeconds: Double = EnemyConfig.fallbackSlashMaxSeconds,
        slashMaxScreenWidthFraction: Double = EnemyConfig.fallbackSlashMaxScreenWidthFraction,
        spriteLibrary: SpriteLibrary,
        letterSpriteSetLibrary: LetterSpriteSetLibrary,
        combatSprite: SpriteConfig?,
        enemySprite: (id: String, config: SpriteConfig)?,
        wallHeight: CGFloat
    ) {
        self.enemyType = enemyType
        self.playerFx = playerFx
        self.startingHealth = startingHealth
        self.letterSoundRepeatSeconds = letterSoundRepeatSeconds
        self.letterSpawnRate = letterSpawnRate
        self.letterCase = letterCase
        self.slashMaxSeconds = slashMaxSeconds
        self.slashMaxScreenWidthFraction = slashMaxScreenWidthFraction
        self.spriteLibrary = spriteLibrary
        self.letterSpriteSetLibrary = letterSpriteSetLibrary
        self.combatSprite = combatSprite
        self.enemySprite = enemySprite
        self.wallHeight = wallHeight
        self.health = startingHealth
    }

    func ensureScene(size: CGSize) {
        guard scene == nil else {
            updateSceneSizeIfNeeded(size)
            return
        }
        let safeSize = Self.sanitizedSize(size)
        let created = CombatScene(
            size: safeSize,
            enemyType: enemyType,
            playerFx: playerFx,
            startingHealth: startingHealth,
            letterSoundRepeatSeconds: letterSoundRepeatSeconds,
            letterSpawnRate: letterSpawnRate,
            letterCase: letterCase,
            slashMaxSeconds: slashMaxSeconds,
            slashMaxScreenWidthFraction: slashMaxScreenWidthFraction,
            spriteLibrary: spriteLibrary,
            letterSpriteSetLibrary: letterSpriteSetLibrary,
            combatSprite: combatSprite,
            enemySprite: enemySprite,
            wallHeight: wallHeight
        )
        created.combatDelegate = self
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

    func confirmVictory(onFinished: (MinigameOutcome) -> Void) {
        guard !didFinish else { return }
        didFinish = true
        onFinished(.won(starsAwarded: starsAwarded))
    }

    func combatSceneDidUpdateStars(_ stars: Int) {
        guard stars != self.stars else { return }
        // SpriteKit callbacks can land during a SwiftUI view update; defer publishes.
        Task { @MainActor in
            self.stars = stars
        }
    }

    func combatSceneDidUpdateHealth(_ health: Int) {
        guard health != self.health else { return }
        Task { @MainActor in
            self.health = health
        }
    }

    func combatSceneDidWin(starsAwarded: Int) {
        self.starsAwarded = starsAwarded
        Task { @MainActor in
            self.showVictory = true
        }
    }

    func combatSceneDidLose() {
        guard !didFinish else { return }
        didFinish = true
        Task { @MainActor in
            self.onLost?()
        }
    }
}
