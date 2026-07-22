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
    /// Called when the player walks onto a destructible wall.
    var onBoomEntered: ((GridCoord) -> Void)?
    /// Called when the player walks onto a gate.
    var onGateEntered: ((GridCoord) -> Void)?
    /// Called after a health/energy pickup finishes its collect animation.
    var onPickupCollected: ((PickupKind) -> Void)?
    /// Called after treasure shake + fade completes.
    var onTreasureCollected: (() -> Void)?
    /// Called with a world snapshot whenever a mid-run save is scheduled.
    var onWorldSaved: ((GameWorld) -> Void)?

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

            if let boomCoord = result.boomCoord {
                isPausedForEncounter = true
                onBoomEntered?(boomCoord)
                break
            }

            if let gateCoord = result.gateCoord {
                isPausedForEncounter = true
                onGateEntered?(gateCoord)
                break
            }

            if let enemyID = result.enemyContactID {
                isPausedForEncounter = true
                onEnemyContact?(enemyID)
                break
            }

            if let pickupID = result.pickupContactID {
                let shouldPause = beginPickupResolution(pickupID: pickupID)
                if shouldPause { break }
            }
        }
    }

    /// Fades the simulation world out (e.g. before an encounter overlay).
    func fadeSimulationOut(duration: TimeInterval = 0.35, completion: @escaping () -> Void) {
        renderer.fadeWorldOut(duration: duration, completion: completion)
    }

    /// Removes the enemy after a fight, fades the simulation back in, then resumes.
    func resolveEnemyEncounter(enemyID: UUID, completion: (() -> Void)? = nil) {
        simulationLoop.removeEnemy(id: enemyID, from: &world)
        pendingInput = PendingInput()
        renderer.syncEntities(world.entities)
        scheduleSave()
        renderer.fadeWorldIn { [weak self] in
            self?.isPausedForEncounter = false
            completion?()
        }
    }

    /// Resumes simulation after the PIT! screen is dismissed.
    func resolvePitEncounter(completion: (() -> Void)? = nil) {
        pendingInput = PendingInput()
        renderer.syncEntities(world.entities)
        scheduleSave()
        renderer.fadeWorldIn { [weak self] in
            self?.isPausedForEncounter = false
            completion?()
        }
    }

    /// Opens a destructible wall after BOOM!, then fades the world back in.
    func resolveBoomEncounter(at coord: GridCoord, completion: (() -> Void)? = nil) {
        _ = world.destroyWall(at: coord)
        pendingInput = PendingInput()
        renderer.render(world: world, focus: viewportFocus)
        scheduleSave()
        renderer.fadeWorldIn { [weak self] in
            self?.isPausedForEncounter = false
            completion?()
        }
    }

    /// Opens a gate strip after GATE ENCOUNTERED!!, then fades the world back in.
    func resolveGateEncounter(at coord: GridCoord, completion: (() -> Void)? = nil) {
        _ = world.openGate(at: coord)
        pendingInput = PendingInput()
        renderer.render(world: world, focus: viewportFocus)
        scheduleSave()
        renderer.fadeWorldIn { [weak self] in
            self?.isPausedForEncounter = false
            completion?()
        }
    }

    /// Renders at YAML tile size with worldScale = 1, centered on the player.
    private func showFixedZoomView() {
        let anchor = world.playerPosition ?? world.spawn
        viewportFocus = IsometricMath.entityScreenPosition(anchor, config: isoConfig)
        renderer.lockWorldScale(1)
        renderer.render(world: world, focus: viewportFocus)
    }

    /// Returns `true` when simulation should pause (treasure only).
    @discardableResult
    private func beginPickupResolution(pickupID: UUID) -> Bool {
        guard let pickup = world.entity(id: pickupID),
              let kind = pickup.pickupKind else { return false }

        switch kind {
        case .health, .energy:
            resolveHealthOrEnergyPickup(id: pickupID, kind: kind)
            return false
        case .treasure:
            isResolvingPickup = true
            pendingInput = PendingInput()
            resolveTreasurePickup(id: pickupID)
            return true
        }
    }

    private func resolveHealthOrEnergyPickup(id: UUID, kind: PickupKind) {
        // Remove immediately so contact can't re-fire and syncEntities won't recreate the sprite.
        // Collect bounce/fade runs on the detached node while the sim keeps ticking.
        _ = world.removeEntity(id: id)
        switch kind {
        case .health:
            world.healthCount += 1
        case .energy:
            world.energyCount += 1
        case .treasure:
            break
        }
        onPickupCollected?(kind)
        renderer.playPickupCollectAnimation(id: id) { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.scheduleSave()
            }
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
        let snapshot = world
        onWorldSaved?(snapshot)
        guard let saveService else { return }
        Task {
            try? await saveService.save(snapshot)
        }
    }
}
