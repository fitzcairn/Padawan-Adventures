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
    let onFinished: (CombatOutcome) -> Void

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
        onFinished: @escaping (CombatOutcome) -> Void
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
                initialTimerSeconds: Int(ceil(enemyType.combatTimerSeconds)),
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
                    CombatSpriteView(scene: scene)
                        .ignoresSafeArea()
                }

                CombatHUDRepresentable(
                    config: hudConfig,
                    healthCount: session.health,
                    progress: session.stars,
                    progressGoal: enemyType.starsToWin,
                    timerSeconds: session.timerSeconds,
                    timerUrgent: session.timerUrgent
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
    @Published var timerSeconds: Int
    @Published var timerUrgent = false
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
        initialTimerSeconds: Int,
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
        self.timerSeconds = initialTimerSeconds
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

    func confirmVictory(onFinished: (CombatOutcome) -> Void) {
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

    func combatSceneDidUpdateTimer(seconds: Int, urgent: Bool) {
        guard seconds != timerSeconds || urgent != timerUrgent else { return }
        Task { @MainActor in
            self.timerSeconds = seconds
            self.timerUrgent = urgent
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

private struct CombatSpriteView: UIViewRepresentable {
    let scene: CombatScene

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

private struct CombatHUDRepresentable: UIViewRepresentable {
    let config: HudConfig
    let healthCount: Int
    let progress: Int
    let progressGoal: Int
    let timerSeconds: Int
    let timerUrgent: Bool

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
            progress: progress,
            progressGoal: progressGoal,
            timerSeconds: timerSeconds
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
        context.coordinator.hud?.setProgress(current: progress, goal: progressGoal)
        context.coordinator.hud?.setTimer(seconds: timerSeconds, urgent: timerUrgent)
    }
}
