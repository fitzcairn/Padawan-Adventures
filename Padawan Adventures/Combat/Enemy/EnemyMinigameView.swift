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
    let slashMaxSeconds: Double
    let onFinished: (CombatOutcome) -> Void

    @StateObject private var session: CombatSessionController

    init(
        enemyType: EnemyTypeConfig,
        healthCount: Int,
        playerFx: SoundEffectTable,
        hudConfig: HudConfig,
        letterSoundRepeatSeconds: Double = CombatMinigameEngine.Config.defaultLetterSoundRepeatSeconds,
        slashMaxSeconds: Double = EnemyConfig.fallbackSlashMaxSeconds,
        onFinished: @escaping (CombatOutcome) -> Void
    ) {
        self.enemyType = enemyType
        self.healthCount = healthCount
        self.playerFx = playerFx
        self.hudConfig = hudConfig
        self.letterSoundRepeatSeconds = letterSoundRepeatSeconds
        self.slashMaxSeconds = slashMaxSeconds
        self.onFinished = onFinished
        _session = StateObject(
            wrappedValue: CombatSessionController(
                enemyType: enemyType,
                playerFx: playerFx,
                startingHealth: healthCount,
                letterSoundRepeatSeconds: letterSoundRepeatSeconds,
                slashMaxSeconds: slashMaxSeconds,
                initialTimerSeconds: Int(ceil(enemyType.combatTimerSeconds))
            )
        )
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()

                if let scene = session.scene {
                    CombatSpriteView(scene: scene)
                        .ignoresSafeArea()
                }

                CombatHUDRepresentable(
                    config: hudConfig,
                    healthCount: session.health,
                    stars: session.stars,
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
    private let slashMaxSeconds: Double
    private var starsAwarded = 0
    private var didFinish = false

    init(
        enemyType: EnemyTypeConfig,
        playerFx: SoundEffectTable,
        startingHealth: Int,
        letterSoundRepeatSeconds: Double = CombatMinigameEngine.Config.defaultLetterSoundRepeatSeconds,
        slashMaxSeconds: Double = EnemyConfig.fallbackSlashMaxSeconds,
        initialTimerSeconds: Int
    ) {
        self.enemyType = enemyType
        self.playerFx = playerFx
        self.startingHealth = startingHealth
        self.letterSoundRepeatSeconds = letterSoundRepeatSeconds
        self.slashMaxSeconds = slashMaxSeconds
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
            slashMaxSeconds: slashMaxSeconds
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
    let stars: Int
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
            starsCount: stars,
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
        context.coordinator.hud?.setStars(stars)
        context.coordinator.hud?.setTimer(seconds: timerSeconds, urgent: timerUrgent)
    }
}
