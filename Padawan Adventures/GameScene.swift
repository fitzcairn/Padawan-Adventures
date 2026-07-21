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
    private var simulationLoop: SimulationLoop
    private var pendingInput = PendingInput()
    private var renderer: IsometricRenderer
    private var viewportFocus = CGPoint.zero
    private var gestureTracker = ViewportGestureTracker()
    private var lastUpdateTime: TimeInterval?
    private let saveService: GameSaveService?

    /// Player must stay within this many tiles of screen center.
    private static let cameraDeadzoneTiles: Double = 2

    init(
        size: CGSize,
        world: GameWorld,
        isoConfig: IsometricConfig,
        saveService: GameSaveService?
    ) {
        self.world = world
        self.isoConfig = isoConfig
        self.saveService = saveService
        self.simulationLoop = SimulationLoop(isoConfig: isoConfig)
        self.renderer = IsometricRenderer(config: isoConfig)
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
        guard let touch = touches.first else { return }
        gestureTracker.begin(at: touch.location(in: self))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
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
        }
    }

    /// Renders at YAML tile size with worldScale = 1, centered on the player.
    private func showFixedZoomView() {
        let anchor = world.playerPosition ?? world.spawn
        viewportFocus = IsometricMath.entityScreenPosition(anchor, config: isoConfig)
        renderer.lockWorldScale(1)
        renderer.render(world: world, focus: viewportFocus)
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

        if let player = world.entities.first(where: \.isPlayer),
           player.position.story == renderer.visibleStory {
            renderer.syncEntities(world.entities)
            renderer.updateEntityDisplayPosition(
                player,
                screenPosition: displayPoint,
                sortCoord: occupancy
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
