//
//  GameScene.swift
//  Padawan Adventures
//

import SpriteKit

final class GameScene: SKScene {
    private var world = GameWorld(
        width: 1,
        height: 1,
        tiles: [[[
            Tile(kind: .floor(isPit: false)),
        ]]],
        entities: [GameEntity(letter: "P", position: GridCoord(x: 0, y: 0, story: 0), isPlayer: true)],
        spawn: GridCoord(x: 0, y: 0, story: 0)
    )
    private var movement = MovementSystem()
    private var simulationClock = SimulationClock()
    private var simulationLoop = SimulationLoop()
    private var pendingInput = PendingInput()
    private let renderer = IsometricRenderer()
    private let isoConfig = IsometricConfig()
    private var viewportFocus = CGPoint.zero
    private var followPlayer = true
    private var gestureTracker = ViewportGestureTracker()
    private var lastUpdateTime: TimeInterval?
    private let saveService: GameSaveService?

    override init(size: CGSize) {
        saveService = try? GameSaveService()
        super.init(size: size)
    }

    required init?(coder aDecoder: NSCoder) {
        saveService = try? GameSaveService()
        super.init(coder: aDecoder)
    }

    override func didMove(to view: SKView) {
        // Non-reachable void reads as black; pits and doors stay transparent over it.
        backgroundColor = .black
        anchorPoint = CGPoint(x: 0.5, y: 0.5)

        renderer.attach(to: self)

        Task { @MainActor in
            await bootstrapWorld()
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        gestureTracker.begin(at: touch.location(in: self))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first,
              let delta = gestureTracker.move(to: touch.location(in: self)) else { return }

        followPlayer = false
        viewportFocus = IsometricMath.focusAfterPan(currentFocus: viewportFocus, dragDelta: delta)
        renderer.updateViewportFocus(viewportFocus)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let wasTap = gestureTracker.end()
        guard wasTap else { return }

        guard let touch = touches.first,
              let playerPosition = world.playerPosition else { return }

        let location = touch.location(in: self)
        let target = IsometricMath.gridFromView(
            location,
            focus: viewportFocus,
            viewCenter: renderer.sceneViewCenter,
            story: playerPosition.story,
            config: isoConfig
        )

        guard world.isInBounds(target), world.isEnterable(at: target) else { return }
        followPlayer = true
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

    @MainActor
    private func bootstrapWorld() async {
        do {
            if let saveService, let restored = try await saveService.load() {
                world = restored
            } else {
                world = try WorldLoader.loadFromBundle()
            }
        } catch {
            world = (try? ProceduralGenerator().generate(from: Self.fallbackConfig()))
                ?? world
        }

        simulationClock = SimulationClock()
        movement = MovementSystem()
        pendingInput = PendingInput()
        followPlayer = true

        let anchor = world.playerPosition ?? world.spawn
        viewportFocus = IsometricMath.entityScreenPosition(anchor, config: isoConfig)
        renderer.render(world: world, focus: viewportFocus)
    }

    private func applyTickResult(_ result: SimulationTickResult) {
        let occupancy = result.playerDisplayCoord ?? world.playerPosition ?? world.spawn
        let displayPoint = result.playerDisplayPoint
            ?? IsometricMath.entityScreenPosition(occupancy, config: isoConfig)

        if followPlayer {
            viewportFocus = displayPoint
        }

        // Show only the story the player currently occupies.
        let rebuiltForStory = renderer.updateVisibleStory(for: world, focus: viewportFocus)
        if !rebuiltForStory, followPlayer {
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

    private static func fallbackConfig() -> WorldSeedConfig {
        WorldSeedConfig(
            version: 1,
            seed: 42,
            world: .init(width: 24, height: 24, stories: 2),
            generation: .init(
                algorithm: "rooms_doors",
                roomCount: 6,
                corridorWidth: 1,
                minRoomSize: 5,
                maxRoomSize: 10,
                pitChance: 0.05,
                wallDestructibleChance: 0.2,
                rampCount: 2,
                ladderCount: 2,
                slideCount: 1,
                doorCount: 4
            ),
            player: .init(letter: "P", spawn: nil),
            extensions: nil
        )
    }
}
