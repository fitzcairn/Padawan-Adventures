//
//  GameScene.swift
//  Padawan Adventures
//

import SpriteKit

final class GameScene: SKScene {
    var world: GameWorld
    var movement = MovementSystem()
    private var simulationClock = SimulationClock()
    var isoConfig: IsometricConfig
    let enemyConfig: EnemyConfig
    let playerFx: SoundEffectTable
    let worldFx: SoundEffectTable
    let spriteLibrary: SpriteLibrary?
    var simulationLoop: SimulationLoop
    var pendingInput = PendingInput()
    var renderer: IsometricRenderer
    var viewportFocus = CGPoint.zero
    var gestureTracker = ViewportGestureTracker()
    var viewportCamera = ViewportCamera()
    private var lastUpdateTime: TimeInterval?
    let saveService: GameSaveService?
    var isPausedForEncounter = false
    var isResolvingPickup = false
    /// Set while the world tutorial drives the camera, so player follow
    /// cannot yank the view back mid-demonstration.
    var tutorialOwnsCamera = false
    weak var worldTutorial: WorldTutorialController?
    var continuePoint: ContinuePointStore
    /// Last movement facing; drives idle when the player stops.
    var playerFacing: CompassDirection = .down
    /// Last known facing per enemy so a stopped enemy keeps facing where it walked.
    var enemyFacings: [UUID: CompassDirection] = [:]

    /// Called when the player contacts an enemy (same occupancy tile).
    var onEnemyContact: ((UUID) -> Void)?
    /// Called the first time an enemy acquires line of sight on the player.
    var onEnemyNoticed: ((UUID) -> Void)?
    /// Called when the player contacts the merchant (same occupancy tile).
    var onMerchantContact: ((_ merchantID: UUID, _ approach: GridCoord) -> Void)?
    /// Called when the player enters a pit tile (`approach` retreat tile).
    var onPitEntered: ((_ approach: GridCoord) -> Void)?
    /// Called when the player walks onto a gate (`gate` tile, `approach` retreat tile).
    var onGateEntered: ((_ gate: GridCoord, _ approach: GridCoord) -> Void)?
    /// Called after a health/energy pickup finishes its collect animation.
    var onPickupCollected: ((PickupKind) -> Void)?
    /// Called when the treasure celebration animation (and victory music) should start.
    var onTreasureCelebrationStarted: (() -> Void)?
    /// Called after treasure shake, celebrate, and fade complete.
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
    static let cameraDeadzoneTiles: Double = 2

    init(
        size: CGSize,
        world: GameWorld,
        isoConfig: IsometricConfig,
        enemyConfig: EnemyConfig = .fallback,
        npcsConfig: NpcsConfig = .fallback,
        playerFx: SoundEffectTable = .empty,
        worldFx: SoundEffectTable = .empty,
        spriteLibrary: SpriteLibrary? = nil,
        playerSpriteConfig: SpriteConfig? = nil,
        itemsConfig: ItemsConfig? = nil,
        treasureItemID: String? = nil,
        floorTileSetLibrary: FloorTileSetLibrary? = nil,
        gateSpriteSetLibrary: GateSpriteSetLibrary? = nil,
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
            npcsConfig: npcsConfig,
            spriteLibrary: spriteLibrary,
            playerSpriteConfig: playerSpriteConfig,
            itemsConfig: itemsConfig,
            treasureItemID: treasureItemID,
            floorTileSetLibrary: floorTileSetLibrary,
            gateSpriteSetLibrary: gateSpriteSetLibrary
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
        if worldTutorial != nil, !(touch is MinigameDemoTouch) {
            worldTutorial?.cancel()
        }
        gestureTracker.begin(at: touch.location(in: self))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isPausedForEncounter, !isResolvingPickup else { return }
        guard let touch = touches.first,
              let delta = gestureTracker.move(to: touch.location(in: self)) else { return }

        if !tutorialOwnsCamera {
            viewportCamera.noteUserPan()
        }
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
        guard let target = IsometricMath.pickTravelTarget(
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

        // Tutorial taps must walk only on ordinary floor — never through pits, gates,
        // or occupied cells. The normal Pathfinder treats those as walkable.
        if worldTutorial != nil, touch is MinigameDemoTouch {
            beginTutorialSafeMove(to: target)
        } else {
            pendingInput.enqueue(target)
            beginReturnToPlayerIfNeeded()
        }
        renderer.playTapTarget(at: target)
    }

    /// Begins player movement along a path that stays on ordinary floor tiles only.
    @discardableResult
    func beginTutorialSafeMove(to target: GridCoord) -> Bool {
        guard let start = world.playerPosition,
              let path = WorldTutorialTargetPicker.safePath(from: start, to: target, in: world),
              path.count >= 2 else { return false }
        pendingInput = PendingInput()
        movement.begin(path: path)
        beginReturnToPlayerIfNeeded()
        return true
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

            if let gateCoord = result.gateCoord {
                isPausedForEncounter = true
                let approach = result.gateApproachCoord ?? gateCoord
                onGateEntered?(gateCoord, approach)
                break
            }

            if let enemyID = result.enemyContactID {
                isPausedForEncounter = true
                simulationLoop.beginEnemyEncounter()
                onEnemyContact?(enemyID)
                break
            }

            if let merchantID = result.merchantContactID {
                isPausedForEncounter = true
                simulationLoop.beginEncounter()
                let approach = result.merchantApproachCoord ?? world.spawn
                onMerchantContact?(merchantID, approach)
                break
            }

            if let pickupID = result.pickupContactID {
                let shouldPause = beginPickupResolution(pickupID: pickupID)
                if shouldPause { break }
            }
        }

        if !isPausedForEncounter, !isResolvingPickup {
            applyViewportCamera(deltaTime: delta)
        }
    }

    var isPlayerMoving: Bool { movement.isMoving }

    func setViewportFocus(_ point: CGPoint) {
        viewportFocus = point
        renderer.updateViewportFocus(point)
    }

    /// After a pan, a destination tap glides the viewport back onto the player.
    func beginReturnToPlayerIfNeeded() {
        guard !tutorialOwnsCamera else { return }
        viewportCamera.noteDestinationChosen(from: viewportFocus)
    }

    /// Clears tutorial state and any half-finished synthetic gesture.
    func finishWorldTutorial() {
        tutorialOwnsCamera = false
        viewportCamera.snapToFollowing()
        gestureTracker.cancel()
        worldTutorial = nil
    }

    /// Fades the simulation world out (e.g. before an encounter overlay).
    func fadeSimulationOut(
        duration: TimeInterval = WorldFade.duration,
        completion: @escaping () -> Void
    ) {
        renderer.fadeWorldOut(duration: duration, completion: completion)
    }

    /// Fades the simulation world in (e.g. during overlay→world crossfade).
    func fadeSimulationIn(
        duration: TimeInterval = WorldFade.duration,
        completion: @escaping () -> Void
    ) {
        renderer.fadeWorldIn(duration: duration, completion: completion)
    }
}
