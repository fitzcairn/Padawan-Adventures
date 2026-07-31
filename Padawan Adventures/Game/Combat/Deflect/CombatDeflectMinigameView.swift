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
    let wallHeight: CGFloat
    let isoSquash: CGFloat
    let onFinished: (CombatOutcome) -> Void

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
        wallHeight: CGFloat,
        isoSquash: CGFloat,
        onFinished: @escaping (CombatOutcome) -> Void
    ) {
        self.deflectConfig = deflectConfig
        self.enemyType = enemyType
        self.healthCount = healthCount
        self.playerFx = playerFx
        self.hudConfig = hudConfig
        self.spriteLibrary = spriteLibrary
        self.combatSprite = combatSprite
        self.enemySprite = enemySprite
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
                wallHeight: wallHeight,
                isoSquash: isoSquash
            )
        )
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                OverlayChrome.backgroundColor.ignoresSafeArea()

                if let scene = session.scene {
                    CombatDeflectSpriteView(scene: scene)
                        .ignoresSafeArea()
                }

                // Hearts only — monster HP is drawn in-scene beside the enemy.
                CombatDeflectHUDRepresentable(
                    config: hudConfig,
                    healthCount: session.health
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                // HUD must not steal taps from the SpriteKit rings underneath.
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
final class CombatDeflectSessionController: ObservableObject, CombatDeflectSceneDelegate {
    @Published var health: Int
    @Published var monsterHP: Int
    @Published var monsterHPTotal: Int
    @Published var showVictory = false
    @Published private(set) var scene: CombatDeflectScene?

    var onLost: (() -> Void)?

    private let deflectConfig: CombatDeflectConfig
    private let enemyType: EnemyTypeConfig
    private let playerFx: SoundEffectTable
    private let startingHealth: Int
    private let spriteLibrary: SpriteLibrary
    private let combatSprite: SpriteConfig?
    private let enemySprite: (id: String, config: SpriteConfig)?
    private let wallHeight: CGFloat
    private let isoSquash: CGFloat
    private var starsAwarded = 0
    private var didFinish = false

    init(
        deflectConfig: CombatDeflectConfig,
        enemyType: EnemyTypeConfig,
        playerFx: SoundEffectTable,
        startingHealth: Int,
        spriteLibrary: SpriteLibrary,
        combatSprite: SpriteConfig?,
        enemySprite: (id: String, config: SpriteConfig)?,
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
        self.wallHeight = wallHeight
        self.isoSquash = isoSquash
        self.health = startingHealth
        self.monsterHP = deflectConfig.monsterHP
        self.monsterHPTotal = deflectConfig.monsterHP
    }

    func ensureScene(size: CGSize) {
        guard scene == nil else {
            updateSceneSizeIfNeeded(size)
            return
        }
        let created = CombatDeflectScene(
            size: Self.sanitizedSize(size),
            deflectConfig: deflectConfig,
            enemyType: enemyType,
            playerFx: playerFx,
            startingHealth: startingHealth,
            spriteLibrary: spriteLibrary,
            combatSprite: combatSprite,
            enemySprite: enemySprite,
            wallHeight: wallHeight,
            isoSquash: isoSquash
        )
        created.deflectDelegate = self
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

    func confirmVictory(onFinished: (CombatOutcome) -> Void) {
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

private struct CombatDeflectSpriteView: UIViewRepresentable {
    let scene: CombatDeflectScene

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

private struct CombatDeflectHUDRepresentable: UIViewRepresentable {
    let config: HudConfig
    let healthCount: Int

    final class Coordinator {
        var hud: CombatHUDView?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        // SwiftUI sizes this container via autoresizing; the HUD is pinned inside.
        let container = UIView()
        container.backgroundColor = .clear
        container.isUserInteractionEnabled = false

        let hud = CombatHUDView(
            config: config,
            healthCount: healthCount,
            showsProgressBar: false
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
        context.coordinator.hud?.setHealth(healthCount)
    }
}
