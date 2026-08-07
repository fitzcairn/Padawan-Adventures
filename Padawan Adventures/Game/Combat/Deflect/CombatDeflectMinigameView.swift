import Combine
import SpriteKit
import SwiftUI
import UIKit

struct CombatDeflectMinigameView: View {
    let deflectConfig: CombatDeflectConfig
    let enemyType: EnemyTypeConfig
    let healthCount: Int
    let playerFx: SoundEffectTable
    let hudConfig: HudConfig
    let spriteLibrary: SpriteLibrary
    let combatSprite: SpriteConfig?
    let enemySprite: (id: String, config: SpriteConfig)?
    let projectileSprite: (id: String, config: SpriteConfig)?
    let wallHeight: CGFloat
    let isoSquash: CGFloat
    let onFinished: (MinigameOutcome) -> Void

    @StateObject private var session: CombatDeflectSessionController

    init(
        deflectConfig: CombatDeflectConfig,
        enemyType: EnemyTypeConfig,
        healthCount: Int,
        playerFx: SoundEffectTable,
        hudConfig: HudConfig,
        spriteLibrary: SpriteLibrary,
        combatSprite: SpriteConfig?,
        enemySprite: (id: String, config: SpriteConfig)?,
        projectileSprite: (id: String, config: SpriteConfig)?,
        wallHeight: CGFloat,
        isoSquash: CGFloat,
        onFinished: @escaping (MinigameOutcome) -> Void
    ) {
        self.deflectConfig = deflectConfig
        self.enemyType = enemyType
        self.healthCount = healthCount
        self.playerFx = playerFx
        self.hudConfig = hudConfig
        self.spriteLibrary = spriteLibrary
        self.combatSprite = combatSprite
        self.enemySprite = enemySprite
        self.projectileSprite = projectileSprite
        self.wallHeight = wallHeight
        self.isoSquash = isoSquash
        self.onFinished = onFinished
        _session = StateObject(
            wrappedValue: CombatDeflectSessionController(
                deflectConfig: deflectConfig,
                enemyType: enemyType,
                playerFx: playerFx,
                startingHealth: healthCount,
                spriteLibrary: spriteLibrary,
                combatSprite: combatSprite,
                enemySprite: enemySprite,
                projectileSprite: projectileSprite,
                wallHeight: wallHeight,
                isoSquash: isoSquash
            )
        )
    }

    private var rootID: String {
        deflectConfig.letterPosition == .ending
            ? "minigame.enemy.ending_sound"
            : "minigame.enemy.deflect"
    }

    var body: some View {
        MinigameShellView(
            scene: session.scene,
            accessibilityRootID: rootID,
            ensureScene: session.ensureScene(size:),
            updateSceneSize: session.updateSceneSizeIfNeeded(_:),
            onAppear: { session.onLost = { onFinished(.lost) } },
            hud: {
                HUDHostRepresentable(
                    makeHUD: {
                        CombatHUDView(
                            config: hudConfig,
                            healthCount: session.health,
                            showsProgressBar: false
                        )
                    },
                    update: { hud in
                        hud.setHealth(session.health)
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
final class CombatDeflectSessionController: ObservableObject, CombatDeflectSceneDelegate {
    @Published var health: Int
    @Published var monsterHP: Int
    @Published var monsterHPTotal: Int
    @Published var showVictory = false
    @Published private(set) var starsAwarded = 0
    @Published private(set) var scene: CombatDeflectScene?

    var onLost: (() -> Void)?

    private let deflectConfig: CombatDeflectConfig
    private let enemyType: EnemyTypeConfig
    private let playerFx: SoundEffectTable
    private let startingHealth: Int
    private let spriteLibrary: SpriteLibrary
    private let combatSprite: SpriteConfig?
    private let enemySprite: (id: String, config: SpriteConfig)?
    private let projectileSprite: (id: String, config: SpriteConfig)?
    private let wallHeight: CGFloat
    private let isoSquash: CGFloat
    private var didFinish = false
    private lazy var sceneHost = MinigameSceneHost<CombatDeflectScene>(
        make: { [deflectConfig, enemyType, playerFx, startingHealth, spriteLibrary, combatSprite, enemySprite, projectileSprite, wallHeight, isoSquash] size in
            CombatDeflectScene(
                size: size,
                deflectConfig: deflectConfig,
                enemyType: enemyType,
                playerFx: playerFx,
                startingHealth: startingHealth,
                spriteLibrary: spriteLibrary,
                combatSprite: combatSprite,
                enemySprite: enemySprite,
                projectileSprite: projectileSprite,
                wallHeight: wallHeight,
                isoSquash: isoSquash
            )
        },
        onReady: { [weak self] created in
            guard let self else { return }
            created.deflectDelegate = self
            self.scene = created
        }
    )

    init(
        deflectConfig: CombatDeflectConfig,
        enemyType: EnemyTypeConfig,
        playerFx: SoundEffectTable,
        startingHealth: Int,
        spriteLibrary: SpriteLibrary,
        combatSprite: SpriteConfig?,
        enemySprite: (id: String, config: SpriteConfig)?,
        projectileSprite: (id: String, config: SpriteConfig)?,
        wallHeight: CGFloat,
        isoSquash: CGFloat
    ) {
        self.deflectConfig = deflectConfig
        self.enemyType = enemyType
        self.playerFx = playerFx
        self.startingHealth = startingHealth
        self.spriteLibrary = spriteLibrary
        self.combatSprite = combatSprite
        self.enemySprite = enemySprite
        self.projectileSprite = projectileSprite
        self.wallHeight = wallHeight
        self.isoSquash = isoSquash
        self.health = startingHealth
        self.monsterHP = deflectConfig.monsterHP
        self.monsterHPTotal = deflectConfig.monsterHP
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

    func combatDeflectSceneDidUpdateHealth(_ health: Int) {
        guard health != self.health else { return }
        // SpriteKit callbacks can land during a SwiftUI view update; defer publishes.
        Task { @MainActor in
            self.health = health
        }
    }

    func combatDeflectSceneDidUpdateMonsterHP(_ hp: Int, of total: Int) {
        guard hp != monsterHP || total != monsterHPTotal else { return }
        Task { @MainActor in
            self.monsterHP = hp
            self.monsterHPTotal = total
        }
    }

    func combatDeflectSceneDidWin(starsAwarded: Int) {
        self.starsAwarded = starsAwarded
        Task { @MainActor in
            self.showVictory = true
        }
    }

    func combatDeflectSceneDidLose() {
        guard !didFinish else { return }
        didFinish = true
        Task { @MainActor in
            self.onLost?()
        }
    }
}
