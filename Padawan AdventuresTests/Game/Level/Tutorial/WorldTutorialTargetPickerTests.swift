import Foundation
import Testing
@testable import Padawan_Adventures

struct WorldTutorialTargetPickerTests {
    @Test func picksTileAtLeastTwoCellsFromSpawn() {
        let world = TestWorldFactory.emptyFloor(width: 8, height: 8)
        let target = WorldTutorialTargetPicker.demoTarget(in: world)
        #expect(target != nil)
        guard let target else { return }
        let dx = abs(target.x - world.spawn.x)
        let dy = abs(target.y - world.spawn.y)
        #expect(max(dx, dy) >= 2)
        #expect(target.story == world.spawn.story)
        #expect(WorldTutorialTargetPicker.isSafeFloor(target, in: world))
    }

    @Test func neverReturnsPitOrGate() {
        var world = TestWorldFactory.emptyFloor(width: 6, height: 6)
        // Surround preferred ring with hazards so only safe tiles remain farther out.
        for y in 0..<6 {
            for x in 0..<6 {
                let coord = GridCoord(x: x, y: y, story: 0)
                let distance = max(abs(x - world.spawn.x), abs(y - world.spawn.y))
                if distance == 2 {
                    world.setTile(Tile(kind: .floor(isPit: true)), at: coord)
                } else if distance == 3 {
                    world.setTile(Tile(kind: .gate(minigame: .soundOutWord)), at: coord)
                }
            }
        }

        let target = WorldTutorialTargetPicker.demoTarget(in: world)
        if let target, let tile = world.tile(at: target) {
            #expect(!tile.isPit)
            #expect(!tile.isGate)
            if case .floor(let isPit) = tile.kind {
                #expect(!isPit)
            } else {
                Issue.record("expected ordinary floor, got \(tile.kind)")
            }
        }
    }

    @Test func neverReturnsOccupiedTile() {
        var world = TestWorldFactory.emptyFloor(width: 6, height: 6)
        // Occupy every non-spawn floor cell; picker should return nil.
        var entities = world.entities
        for y in 0..<6 {
            for x in 0..<6 {
                let coord = GridCoord(x: x, y: y, story: 0)
                guard coord != world.spawn else { continue }
                entities.append(
                    GameEntity(letter: "E", position: coord, enemyTypeID: "spider")
                )
            }
        }
        world = GameWorld(
            width: world.width,
            height: world.height,
            storyCount: world.storyCount,
            tiles: world.tiles,
            entities: entities,
            spawn: world.spawn
        )

        #expect(WorldTutorialTargetPicker.demoTarget(in: world) == nil)
    }

    @Test func returnsNilWhenSpawnIsWalledIn() {
        let wall = Tile(kind: .wall)
        let floor = Tile(kind: .floor(isPit: false))
        var tiles = Array(
            repeating: Array(repeating: Array(repeating: wall, count: 5), count: 5),
            count: 1
        )
        tiles[0][2][2] = floor
        let spawn = GridCoord(x: 2, y: 2, story: 0)
        let world = TestWorldFactory.withTiles(tiles, spawn: spawn)
        #expect(WorldTutorialTargetPicker.demoTarget(in: world) == nil)
    }

    @Test func rejectsTargetsWhoseOnlyPathCrossesAPit() {
        // Corridor: spawn - floor - pit - floor. The far floor is reachable via the
        // normal Pathfinder (pits are walkable) but must not be a tutorial target.
        let floor = Tile(kind: .floor(isPit: false))
        let pit = Tile(kind: .floor(isPit: true))
        let wall = Tile(kind: .wall)
        var tiles = Array(
            repeating: Array(repeating: Array(repeating: wall, count: 5), count: 3),
            count: 1
        )
        let spawn = GridCoord(x: 0, y: 1, story: 0)
        tiles[0][1][0] = floor
        tiles[0][1][1] = floor
        tiles[0][1][2] = pit
        tiles[0][1][3] = floor
        let world = TestWorldFactory.withTiles(tiles, spawn: spawn)

        let far = GridCoord(x: 3, y: 1, story: 0)
        #expect(WorldTutorialTargetPicker.safePath(from: spawn, to: far, in: world) == nil)
        let target = WorldTutorialTargetPicker.demoTarget(in: world)
        if let target {
            #expect(target != far)
            #expect(WorldTutorialTargetPicker.isSafeFloor(target, in: world))
            let path = WorldTutorialTargetPicker.safePath(from: spawn, to: target, in: world)
            #expect(path != nil)
            for step in path ?? [] where step != spawn {
                #expect(WorldTutorialTargetPicker.isSafeFloor(step, in: world), "\(step)")
            }
        }
    }

    @Test func safePathNeverStepsOnGateEnemyOrPit() throws {
        var world = TestWorldFactory.emptyFloor(width: 5, height: 5)
        let pit = GridCoord(x: 1, y: 0, story: 0)
        let gate = GridCoord(x: 2, y: 0, story: 0)
        let enemyCell = GridCoord(x: 3, y: 0, story: 0)
        world.setTile(Tile(kind: .floor(isPit: true)), at: pit)
        world.setTile(Tile(kind: .gate(minigame: .soundOutWord)), at: gate)
        world = GameWorld(
            width: world.width,
            height: world.height,
            storyCount: world.storyCount,
            tiles: world.tiles,
            entities: world.entities + [
                GameEntity(letter: "E", position: enemyCell, enemyTypeID: "spider"),
            ],
            spawn: world.spawn
        )

        #expect(WorldTutorialTargetPicker.safePath(from: world.spawn, to: pit, in: world) == nil)
        #expect(WorldTutorialTargetPicker.safePath(from: world.spawn, to: gate, in: world) == nil)
        #expect(WorldTutorialTargetPicker.safePath(from: world.spawn, to: enemyCell, in: world) == nil)

        let safe = GridCoord(x: 0, y: 3, story: 0)
        let path = try #require(
            WorldTutorialTargetPicker.safePath(from: world.spawn, to: safe, in: world)
        )
        for step in path where step != world.spawn {
            #expect(WorldTutorialTargetPicker.isSafeFloor(step, in: world), "\(step)")
            #expect(step != pit)
            #expect(step != gate)
            #expect(step != enemyCell)
        }
    }

    @Test func isDeterministic() {
        let world = TestWorldFactory.emptyFloor(width: 8, height: 8)
        let first = WorldTutorialTargetPicker.demoTarget(in: world)
        let second = WorldTutorialTargetPicker.demoTarget(in: world)
        #expect(first == second)
    }
}
