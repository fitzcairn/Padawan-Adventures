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
    private let playerFx: SoundEffectTable
    private let worldFx: SoundEffectTable
    private let spriteLibrary: SpriteLibrary?
    private var simulationLoop: SimulationLoop
    private var pendingInput = PendingInput()
    private var renderer: IsometricRenderer
    private var viewportFocus = CGPoint.zero
    private var gestureTracker = ViewportGestureTracker()
    private var lastUpdateTime: TimeInterval?
    private let saveService: GameSaveService?
    private var isPausedForEncounter = false
    private var isResolvingPickup = false
    private var continuePoint: ContinuePointStore
    /// Last movement facing; drives idle when the player stops.
    private var playerFacing: CompassDirection = .down
    /// Last known facing per enemy so a stopped enemy keeps facing where it walked.
    private var enemyFacings: [UUID: CompassDirection] = [:]

    /// Called when the player contacts an enemy (same occupancy tile).
    var onEnemyContact: ((UUID) -> Void)?
    /// Called when the player enters a pit tile (`approach` retreat tile).
    var onPitEntered: ((_ approach: GridCoord) -> Void)?
    /// Called when the player walks onto a destructible wall (`wall` tile, `approach` retreat tile).
    var onBoomEntered: ((_ wall: GridCoord, _ approach: GridCoord) -> Void)?
    /// Called when the player walks onto a gate (`gate` tile, `approach` retreat tile).
    var onGateEntered: ((_ gate: GridCoord, _ approach: GridCoord) -> Void)?
    /// Called after a health/energy pickup finishes its collect animation.
    var onPickupCollected: ((PickupKind) -> Void)?
    /// Called after treasure shake + fade completes.
    var onTreasureCollected: (() -> Void)?
    /// Called with a world snapshot whenever a mid-run save is scheduled.
    var onWorldSaved: ((GameWorld) -> Void)?
    /// Called when vitals change due to restore (absolute counts for HUD sync).
    var onVitalsRestored: ((Int, Int) -> Void)?

    /// Snapshot of the live world for persistence (e.g. Menu exit).
    var currentWorld: GameWorld { world }

    /// Last safe continue snapshot (for tests / debugging).
    var lastSafeContinueWorld: GameWorld { continuePoint.snapshot }

    /// Player must stay within this many tiles of screen center.
    private static let cameraDeadzoneTiles: Double = 2

    init(
        size: CGSize,
        world: GameWorld,
        isoConfig: IsometricConfig,
        enemyConfig: EnemyConfig = .fallback,
        playerFx: SoundEffectTable = .empty,
        worldFx: SoundEffectTable = .empty,
        spriteLibrary: SpriteLibrary? = nil,
        playerSpriteConfig: SpriteConfig? = nil,
        itemsConfig: ItemsConfig? = nil,
        floorSpriteLibrary: FloorSpriteLibrary? = nil,
        saveService: GameSaveService?
    ) {
        self.world = world
        self.isoConfig = isoConfig
        self.enemyConfig = enemyConfig
        self.playerFx = playerFx
        self.worldFx = worldFx
        self.spriteLibrary = spriteLibrary
        self.saveService = saveService
        self.continuePoint = ContinuePointStore(world: world)
        self.simulationLoop = SimulationLoop(isoConfig: isoConfig, enemyConfig: enemyConfig)
        self.renderer = IsometricRenderer(
            config: isoConfig,
            enemyConfig: enemyConfig,
            spriteLibrary: spriteLibrary,
            playerSpriteConfig: playerSpriteConfig,
            itemsConfig: itemsConfig,
            floorSpriteLibrary: floorSpriteLibrary
        )
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
                continuePoint.captureIfSafe(world, tick: result)
                // Skip mid-encounter disk saves; resolve* paths write the post-combat checkpoint.
                if result.shouldPersistContinueSave {
                    scheduleSave()
                }
            }

            if result.didEnterPit {
                isPausedForEncounter = true
                let approach = result.pitApproachCoord ?? world.playerPosition ?? world.spawn
                onPitEntered?(approach)
                break
            }

            if let boomCoord = result.boomCoord {
                isPausedForEncounter = true
                let approach = result.boomApproachCoord ?? boomCoord
                onBoomEntered?(boomCoord, approach)
                break
            }

            if let gateCoord = result.gateCoord {
                isPausedForEncounter = true
                let approach = result.gateApproachCoord ?? gateCoord
                onGateEntered?(gateCoord, approach)
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
        captureContinueAndSave()
        renderer.fadeWorldIn { [weak self] in
            self?.isPausedForEncounter = false
            completion?()
        }
    }

    /// Fills the pit blob into ordinary floor after a successful escape, then resumes.
    func resolvePitWin(completion: (() -> Void)? = nil) {
        if let pit = world.playerPosition {
            _ = world.fillPit(at: pit)
        }
        pendingInput = PendingInput()
        renderer.render(world: world, focus: viewportFocus)
        showFixedZoomView()
        captureContinueAndSave()
        renderer.fadeWorldIn { [weak self] in
            self?.isPausedForEncounter = false
            completion?()
        }
    }

    /// Retreats the player to the approach tile after a pit timeout (pit stays).
    func resolvePitTimeout(approach: GridCoord, completion: (() -> Void)? = nil) {
        world.setPlayerPosition(approach)
        pendingInput = PendingInput()
        renderer.syncEntities(world.entities)
        renderer.render(world: world, focus: viewportFocus)
        showFixedZoomView()
        // Do not overwrite Continue — the last safe world remains before the failed attempt.
        renderer.fadeWorldIn { [weak self] in
            self?.isPausedForEncounter = false
            completion?()
        }
    }

    /// Opens a destructible wall after a successful puzzle, then fades the world back in.
    func resolveBoomEncounter(at coord: GridCoord, completion: (() -> Void)? = nil) {
        if world.destroyWall(at: coord) {
            SoundEffectsController.shared.play(event: "wall_destroyed", from: worldFx)
        }
        pendingInput = PendingInput()
        renderer.render(world: world, focus: viewportFocus)
        captureContinueAndSave()
        renderer.fadeWorldIn { [weak self] in
            self?.isPausedForEncounter = false
            completion?()
        }
    }

    /// Retreats the player off the soft wall after a timeout (wall stays intact).
    func resolveBoomTimeout(approach: GridCoord, completion: (() -> Void)? = nil) {
        world.setPlayerPosition(approach)
        pendingInput = PendingInput()
        renderer.syncEntities(world.entities)
        renderer.render(world: world, focus: viewportFocus)
        // Do not overwrite Continue — the last safe world remains before the failed attempt.
        renderer.fadeWorldIn { [weak self] in
            self?.isPausedForEncounter = false
            completion?()
        }
    }

    /// De-spawns a gate strip after a successful puzzle, then fades the world back in.
    func resolveGateEncounter(at coord: GridCoord, completion: (() -> Void)? = nil) {
        if world.openGate(at: coord) {
            SoundEffectsController.shared.play(event: "gate_opened", from: worldFx)
        }
        pendingInput = PendingInput()
        renderer.render(world: world, focus: viewportFocus)
        captureContinueAndSave()
        renderer.fadeWorldIn { [weak self] in
            self?.isPausedForEncounter = false
            completion?()
        }
    }

    /// Retreats the player off the gate after a timeout (gate stays closed).
    func resolveGateTimeout(approach: GridCoord, completion: (() -> Void)? = nil) {
        world.setPlayerPosition(approach)
        pendingInput = PendingInput()
        renderer.syncEntities(world.entities)
        renderer.render(world: world, focus: viewportFocus)
        // Do not overwrite Continue — the last safe world remains before the failed attempt.
        renderer.fadeWorldIn { [weak self] in
            self?.isPausedForEncounter = false
            completion?()
        }
    }

    /// Deducts one energy (no-op at 0). Returns the new energy count.
    /// Does not persist — Continue stays on the last safe world until the encounter resolves.
    @discardableResult
    func deductEnergy() -> Int {
        world.energyCount = max(0, world.energyCount - 1)
        return world.energyCount
    }

    /// Deducts one health (no-op at 0). Returns the new health count.
    /// Does not persist — Continue stays on the last safe world until the encounter resolves.
    @discardableResult
    func deductHealth() -> Int {
        world.healthCount = max(0, world.healthCount - 1)
        return world.healthCount
    }

    /// Restores the world to the last safe continue snapshot and resumes play.
    func restoreFromContinuePoint(completion: (() -> Void)? = nil) {
        world = continuePoint.snapshot
        world.healthCount = DefeatRules.restoredVital(world.healthCount)
        world.energyCount = DefeatRules.restoredVital(world.energyCount)
        world.separateNearbyEnemiesOnRestore()
        movement = MovementSystem()
        pendingInput = PendingInput()
        simulationLoop = SimulationLoop(isoConfig: isoConfig, enemyConfig: enemyConfig)
        showFixedZoomView()
        onVitalsRestored?(world.healthCount, world.energyCount)
        captureContinueAndSave()
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
        updatePlayerSpriteAnimation()
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
                self?.captureContinueAndSave()
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
        for event in result.movementEvents {
            if case .reached = event {
                SoundEffectsController.shared.play(event: "move", from: playerFx)
            }
        }

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
        updatePlayerSpriteAnimation()
        updateEnemySpriteAnimations(poses: result.enemyDisplayPoses)
    }

    private func updatePlayerSpriteAnimation() {
        guard let library = spriteLibrary,
              let sprite = renderer.playerAnimatedSprite() else { return }

        let locomotion: SpriteLocomotion
        if movement.isMoving,
           let start = movement.segmentStart,
           let end = movement.segmentEnd {
            let dx = end.x - start.x
            let dy = end.y - start.y
            if let facing = CompassDirection(dx: dx, dy: dy) {
                playerFacing = facing
            }
            locomotion = .walk
        } else {
            locomotion = .idle
        }

        let name = playerFacing.animationName(locomotion: locomotion)
        sprite.play(name: name, library: library)
        // Fall back to idle for the same facing when a walk sheet is not loaded yet.
        if sprite.currentAnimationName != name {
            let idleName = playerFacing.animationName(locomotion: .idle)
            sprite.play(name: idleName, library: library)
        }
    }

    private func updateEnemySpriteAnimations(poses: [EntityDisplayPose]) {
        guard let library = spriteLibrary else { return }

        let liveIDs = Set(poses.map(\.entityID))
        enemyFacings = enemyFacings.filter { liveIDs.contains($0.key) }

        for pose in poses {
            guard let entity = world.entity(id: pose.entityID),
                  let typeID = entity.enemyTypeID,
                  let resolved = enemyConfig.spriteConfig(for: typeID),
                  let sprite = renderer.enemyAnimatedSprite(id: pose.entityID) else { continue }

            if let facing = pose.facing {
                enemyFacings[pose.entityID] = facing
            }
            let facing = enemyFacings[pose.entityID] ?? .down
            let locomotion: SpriteLocomotion = pose.isMoving ? .walk : .idle

            let name = facing.animationName(locomotion: locomotion)
            sprite.play(name: name, library: library, libraryID: resolved.id)
            // Fall back to the same facing's idle clip when a walk sheet is missing.
            if sprite.currentAnimationName != name {
                sprite.play(
                    name: facing.animationName(locomotion: .idle),
                    library: library,
                    libraryID: resolved.id
                )
            }
        }
    }

    private func captureContinueAndSave() {
        continuePoint.capture(world)
        scheduleSave()
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

