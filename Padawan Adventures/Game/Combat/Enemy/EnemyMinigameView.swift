import Combine
import SpriteKit
import SwiftUI
import UIKit

struct EnemyMinigameView: View {
    let enemyType: EnemyTypeConfig
    let healthCount: Int
    let playerFx: SoundEffectTable
    let hudConfig: HudConfig
    let graphemeSoundRepeatSeconds: Double
    let minDecoyCount: Int
    let maxDecoyCount: Int
    let graphemeCase: CombatGraphemeCase
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
        graphemeSoundRepeatSeconds: Double = CombatMinigameEngine.Config.defaultGraphemeSoundRepeatSeconds,
        minDecoyCount: Int = CombatMinigameEngine.Config.defaultMinDecoyCount,
        maxDecoyCount: Int = CombatMinigameEngine.Config.defaultMaxDecoyCount,
        graphemeCase: CombatGraphemeCase = .upper,
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
        self.graphemeSoundRepeatSeconds = graphemeSoundRepeatSeconds
        self.minDecoyCount = minDecoyCount
        self.maxDecoyCount = maxDecoyCount
        self.graphemeCase = graphemeCase
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
                graphemeSoundRepeatSeconds: graphemeSoundRepeatSeconds,
                minDecoyCount: minDecoyCount,
                maxDecoyCount: maxDecoyCount,
                graphemeCase: graphemeCase,
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
        MinigameShellView(
            scene: session.scene,
            accessibilityRootID: "minigame.enemy",
            ensureScene: session.ensureScene(size:),
            updateSceneSize: session.updateSceneSizeIfNeeded(_:),
            onAppear: { session.onLost = { onFinished(.lost) } },
            hud: {
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
            },
            overlay: {
                if session.showVictory {
                    MinigameResultOverlay(starsAwarded: session.starsAwarded) {
                        session.confirmVictory(onFinished: onFinished)
                    }
                }
            }
        )
    }
}

@MainActor
final class CombatSessionController: ObservableObject, CombatSceneDelegate {
    @Published var stars = 0
    @Published var health: Int
    @Published var showVictory = false
    @Published private(set) var starsAwarded = 0
    @Published private(set) var scene: CombatScene?

    var onLost: (() -> Void)?

    private let enemyType: EnemyTypeConfig
    private let playerFx: SoundEffectTable
    private let startingHealth: Int
    private let graphemeSoundRepeatSeconds: Double
    private let minDecoyCount: Int
    private let maxDecoyCount: Int
    private let graphemeCase: CombatGraphemeCase
    private let slashMaxSeconds: Double
    private let slashMaxScreenWidthFraction: Double
    private let spriteLibrary: SpriteLibrary
    private let letterSpriteSetLibrary: LetterSpriteSetLibrary
    private let combatSprite: SpriteConfig?
    private let enemySprite: (id: String, config: SpriteConfig)?
    private let wallHeight: CGFloat
    private var didFinish = false
    private lazy var sceneHost = MinigameSceneHost<CombatScene>(
        make: { [enemyType, playerFx, startingHealth, graphemeSoundRepeatSeconds, minDecoyCount, maxDecoyCount, graphemeCase, slashMaxSeconds, slashMaxScreenWidthFraction, spriteLibrary, letterSpriteSetLibrary, combatSprite, enemySprite, wallHeight] size in
            CombatScene(
                size: size,
                enemyType: enemyType,
                playerFx: playerFx,
                startingHealth: startingHealth,
                graphemeSoundRepeatSeconds: graphemeSoundRepeatSeconds,
                minDecoyCount: minDecoyCount,
                maxDecoyCount: maxDecoyCount,
                graphemeCase: graphemeCase,
                slashMaxSeconds: slashMaxSeconds,
                slashMaxScreenWidthFraction: slashMaxScreenWidthFraction,
                spriteLibrary: spriteLibrary,
                letterSpriteSetLibrary: letterSpriteSetLibrary,
                combatSprite: combatSprite,
                enemySprite: enemySprite,
                wallHeight: wallHeight
            )
        },
        onReady: { [weak self] created in
            guard let self else { return }
            created.combatDelegate = self
            self.scene = created
        }
    )

    init(
        enemyType: EnemyTypeConfig,
        playerFx: SoundEffectTable,
        startingHealth: Int,
        graphemeSoundRepeatSeconds: Double = CombatMinigameEngine.Config.defaultGraphemeSoundRepeatSeconds,
        minDecoyCount: Int = CombatMinigameEngine.Config.defaultMinDecoyCount,
        maxDecoyCount: Int = CombatMinigameEngine.Config.defaultMaxDecoyCount,
        graphemeCase: CombatGraphemeCase = .upper,
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
        self.graphemeSoundRepeatSeconds = graphemeSoundRepeatSeconds
        self.minDecoyCount = minDecoyCount
        self.maxDecoyCount = maxDecoyCount
        self.graphemeCase = graphemeCase
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
        sceneHost.ensureScene(size: size)
    }

    func updateSceneSizeIfNeeded(_ size: CGSize) {
        sceneHost.updateSceneSizeIfNeeded(size)
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
