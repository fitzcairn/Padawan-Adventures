//
//  GameScene.swift
//  Padawan Adventures
//

import SpriteKit

final class GameScene: SKScene {
    private var world: GameWorld
    private var movement = MovementSystem()
    private var simulationClock = SimulationClock()
    private var isoConfig: IsometricConfig
    private let enemyConfig: EnemyConfig
    private var simulationLoop: SimulationLoop
    private var pendingInput = PendingInput()
    private var renderer: IsometricRenderer
    private var viewportFocus = CGPoint.zero
    private var gestureTracker = ViewportGestureTracker()
    private var lastUpdateTime: TimeInterval?
    private let saveService: GameSaveService?
    private var isPausedForEncounter = false
    private var isResolvingPickup = false

    /// Called when the player contacts an enemy (same occupancy tile).
    var onEnemyContact: ((UUID) -> Void)?
    /// Called when the player enters a pit tile.
    var onPitEntered: (() -> Void)?
    /// Called after a health/energy pickup finishes its collect animation.
    var onPickupCollected: ((PickupKind) -> Void)?
    /// Called after treasure shake + fade completes.
    var onTreasureCollected: (() -> Void)?

    /// Snapshot of the live world for persistence (e.g. Menu exit).
    var currentWorld: GameWorld { world }

    /// Player must stay within this many tiles of screen center.
    private static let cameraDeadzoneTiles: Double = 2

    init(
        size: CGSize,
        world: GameWorld,
        isoConfig: IsometricConfig,
        enemyConfig: EnemyConfig = .fallback,
        saveService: GameSaveService?
    ) {
        self.world = world
        self.isoConfig = isoConfig
        self.enemyConfig = enemyConfig
        self.saveService = saveService
        self.simulationLoop = SimulationLoop(isoConfig: isoConfig, enemyConfig: enemyConfig)
        self.renderer = IsometricRenderer(config: isoConfig, enemyConfig: enemyConfig)
        super.init(size: size)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        backgroundColor = .black
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        renderer.attach(to: self)
        showFixedZoomView()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isPausedForEncounter, !isResolvingPickup else { return }
        guard let touch = touches.first else { return }
        gestureTracker.begin(at: touch.location(in: self))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isPausedForEncounter, !isResolvingPickup else { return }
        guard let touch = touches.first,
              let delta = gestureTracker.move(to: touch.location(in: self)) else { return }

        viewportFocus = IsometricMath.focusAfterPan(
            currentFocus: viewportFocus,
            dragDelta: delta,
            scale: renderer.worldScale
        )
        renderer.updateViewportFocus(viewportFocus)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isPausedForEncounter, !isResolvingPickup else { return }
        let wasTap = gestureTracker.end()
        guard wasTap else { return }

        guard let touch = touches.first else { return }

        let location = touch.location(in: self)
        guard let target = IsometricMath.pickTile(
            at: location,
            focus: viewportFocus,
            viewCenter: renderer.sceneViewCenter,
            story: renderer.visibleStory,
            in: world,
            scale: renderer.worldScale,
            config: isoConfig
        ) else {
            return
        }

        pendingInput.enqueue(target)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        gestureTracker.cancel()
    }

    override func update(_ currentTime: TimeInterval) {
        let delta: TimeInterval
        if let lastUpdateTime {
            delta = currentTime - lastUpdateTime
        } else {
            delta = 0
        }
        lastUpdateTime = currentTime

        guard !isPausedForEncounter, !isResolvingPickup else { return }

        let ticksToRun = simulationClock.advance(deltaTime: delta)

        for _ in 0..<ticksToRun {
            simulationClock.registerTick()
            let result = simulationLoop.tick(
                world: &world,
                movement: &movement,
                pendingInput: &pendingInput,
                tickCount: simulationClock.tickCount
            )
            applyTickResult(result)

            if result.shouldPersist {
                scheduleSave()
            }

            if result.didEnterPit {
                isPausedForEncounter = true
                onPitEntered?()
                break
            }

            if let enemyID = result.enemyContactID {
                isPausedForEncounter = true
                onEnemyContact?(enemyID)
                break
            }

            if let pickupID = result.pickupContactID {
                beginPickupResolution(pickupID: pickupID)
                break
            }
        }
    }

    /// Removes the enemy after a fight and resumes simulation.
    func resolveEnemyEncounter(enemyID: UUID) {
        simulationLoop.removeEnemy(id: enemyID, from: &world)
        isPausedForEncounter = false
        pendingInput = PendingInput()
        renderer.syncEntities(world.entities)
        scheduleSave()
    }

    /// Resumes simulation after the PIT! screen is dismissed.
    func resolvePitEncounter() {
        isPausedForEncounter = false
        pendingInput = PendingInput()
        renderer.syncEntities(world.entities)
        scheduleSave()
    }

    /// Renders at YAML tile size with worldScale = 1, centered on the player.
    private func showFixedZoomView() {
        let anchor = world.playerPosition ?? world.spawn
        viewportFocus = IsometricMath.entityScreenPosition(anchor, config: isoConfig)
        renderer.lockWorldScale(1)
        renderer.render(world: world, focus: viewportFocus)
    }

    private func beginPickupResolution(pickupID: UUID) {
        guard let pickup = world.entity(id: pickupID),
              let kind = pickup.pickupKind else { return }

        isResolvingPickup = true
        pendingInput = PendingInput()

        switch kind {
        case .health, .energy:
            resolveHealthOrEnergyPickup(id: pickupID, kind: kind)
        case .treasure:
            resolveTreasurePickup(id: pickupID)
        }
    }

    private func resolveHealthOrEnergyPickup(id: UUID, kind: PickupKind) {
        renderer.playPickupCollectAnimation(id: id) { [weak self] in
            guard let self else { return }
            _ = self.world.removeEntity(id: id)
            switch kind {
            case .health:
                self.world.healthCount += 1
            case .energy:
                self.world.energyCount += 1
            case .treasure:
                break
            }
            self.renderer.syncEntities(self.world.entities)
            self.onPickupCollected?(kind)
            self.scheduleSave()
            self.isResolvingPickup = false
        }
    }

    private func resolveTreasurePickup(id: UUID) {
        _ = world.removeEntity(id: id)
        renderer.syncEntities(world.entities)
        renderer.shakeWorld { [weak self] in
            guard let self else { return }
            self.renderer.fadeWorld { [weak self] in
                guard let self else { return }
                self.onTreasureCollected?()
                self.scheduleSave()
            }
        }
    }

    private func applyTickResult(_ result: SimulationTickResult) {
        let occupancy = result.playerDisplayCoord ?? world.playerPosition ?? world.spawn
        let displayPoint = result.playerDisplayPoint
            ?? IsometricMath.entityScreenPosition(occupancy, config: isoConfig)

        let rebuiltForStory = renderer.updateVisibleStory(for: world, focus: viewportFocus)
        if rebuiltForStory {
            viewportFocus = IsometricMath.entityScreenPosition(occupancy, config: isoConfig)
            renderer.lockWorldScale(1)
            renderer.updateViewportFocus(viewportFocus)
        } else if !gestureTracker.isPanning {
            viewportFocus = IsometricMath.focusKeepingPlayerInDeadzone(
                focus: viewportFocus,
                player: displayPoint,
                story: occupancy.story,
                maxTiles: Self.cameraDeadzoneTiles,
                config: isoConfig
            )
            renderer.updateViewportFocus(viewportFocus)
        }

        renderer.syncEntities(world.entities)

        if let player = world.entities.first(where: \.isPlayer),
           player.position.story == renderer.visibleStory {
            renderer.updateEntityDisplayPosition(
                player,
                screenPosition: displayPoint,
                sortCoord: occupancy
            )
        }

        for pose in result.enemyDisplayPoses {
            guard let entity = world.entity(id: pose.entityID),
                  entity.position.story == renderer.visibleStory else { continue }
            renderer.updateEntityDisplayPosition(
                entity,
                screenPosition: pose.screenPosition,
                sortCoord: pose.occupancy
            )
        }

        renderer.applyAnimation(to: world.entities, frame: result.animationFrame)
    }

    private func scheduleSave() {
        guard let saveService else { return }
        let snapshot = world
        Task {
            try? await saveService.save(snapshot)
        }
    }
}
