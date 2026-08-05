import CoreGraphics
import Testing
@testable import Padawan_Adventures

struct PitResolutionTests {
    @Test func pitIsAlwaysHazard() {
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        let pit = GridCoord(x: 1, y: 1, story: 0)
        world.setTile(Tile(kind: .floor(isPit: true)), at: pit)
        world.setPlayerPosition(pit)

        let resolution = world.resolvePit(at: pit)
        #expect(resolution == .hazard)
        #expect(world.playerPosition == pit)
    }

    @Test func enteringHazardPitStopsMovementAndStaysOnPit() {
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        let start = GridCoord(x: 0, y: 1, story: 0)
        let pit = GridCoord(x: 1, y: 1, story: 0)
        world.setTile(Tile(kind: .floor(isPit: true)), at: pit)
        world.setPlayerPosition(start)

        var movement = MovementSystem(tilesPerSecond: 1.0)
        movement.begin(path: [start, pit])

        let events = movement.update(deltaTime: 10, world: &world)
        #expect(events.contains(.pit(resolution: .hazard, approach: start)))
        #expect(world.playerPosition == pit)
        #expect(movement.isMoving == false)
        // Display stays at the approach border instead of snapping to the pit center.
        #expect(abs(movement.segmentProgress - 0.5) < 0.000_001)
        #expect(
            movement.interpolatedScreenPosition(in: world)
                == IsometricMath.entityScreenPosition(x: 0.5, y: 1.0, story: 0)
        )
    }

    @Test func nearestNonPitTileFindsAdjacentFloorAcrossPitBlob() {
        var world = TestWorldFactory.emptyFloor(width: 5, height: 3)
        let pitA = GridCoord(x: 1, y: 1, story: 0)
        let pitB = GridCoord(x: 2, y: 1, story: 0)
        let rim = GridCoord(x: 3, y: 1, story: 0)
        world.setTile(Tile(kind: .floor(isPit: true)), at: pitA)
        world.setTile(Tile(kind: .floor(isPit: true)), at: pitB)

        // Cardinal BFS returns the first adjacent non-pit floor.
        #expect(world.nearestNonPitTile(from: pitA) == GridCoord(x: 1, y: 0, story: 0))
        #expect(world.nearestNonPitTile(from: pitB) == GridCoord(x: 2, y: 0, story: 0))
        #expect(world.nearestNonPitTile(from: rim) == rim)
    }

    @Test func relocatePlayerOffPitMovesToNearestNonPitFloor() {
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        let pit = GridCoord(x: 1, y: 1, story: 0)
        world.setTile(Tile(kind: .floor(isPit: true)), at: pit)
        world.setPlayerPosition(pit)

        let relocated = world.relocatePlayerOffPit()
        #expect(relocated)
        let position = world.playerPosition
        #expect(position != nil)
        #expect(position != pit)
        if let position {
            #expect(world.tile(at: position)?.isPit != true)
            #expect(abs(position.x - pit.x) + abs(position.y - pit.y) == 1)
        }
    }

    @Test func relocatePlayerOffPitNoopsWhenNotOnPit() {
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        let floor = GridCoord(x: 1, y: 1, story: 0)
        world.setPlayerPosition(floor)

        let relocated = world.relocatePlayerOffPit()
        #expect(!relocated)
        #expect(world.playerPosition == floor)
    }

    @Test func fillPitConvertsContiguousPitBlobToOrdinaryFloor() {
        var world = TestWorldFactory.emptyFloor(width: 5, height: 3)
        let pitA = GridCoord(x: 1, y: 1, story: 0)
        let pitB = GridCoord(x: 2, y: 1, story: 0)
        let otherPit = GridCoord(x: 4, y: 1, story: 0)
        world.setTile(Tile(kind: .floor(isPit: true)), at: pitA)
        world.setTile(Tile(kind: .floor(isPit: true)), at: pitB)
        world.setTile(Tile(kind: .floor(isPit: true)), at: otherPit)

        let filled = world.fillPit(at: pitA)
        #expect(filled)
        #expect(world.tile(at: pitA)?.isPit == false)
        #expect(world.tile(at: pitB)?.isPit == false)
        // Disjoint pit blob is left alone.
        #expect(world.tile(at: otherPit)?.isPit == true)
    }

    @Test func fillPitNoopsOnNonPit() {
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        let floor = GridCoord(x: 1, y: 1, story: 0)
        let filled = world.fillPit(at: floor)
        #expect(!filled)
        #expect(world.tile(at: floor)?.isPit == false)
    }

    @Test func filledPitNoLongerEmitsPitHazardOnEntry() {
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        let start = GridCoord(x: 0, y: 1, story: 0)
        let pit = GridCoord(x: 1, y: 1, story: 0)
        world.setTile(Tile(kind: .floor(isPit: true)), at: pit)
        world.setPlayerPosition(start)
        let filled = world.fillPit(at: pit)
        #expect(filled)

        var movement = MovementSystem(tilesPerSecond: 1.0)
        movement.begin(path: [start, pit])
        let events = movement.update(deltaTime: 10, world: &world)
        let triggeredPit = events.contains { event in
            if case .pit = event { return true }
            return false
        }
        #expect(!triggeredPit)
        #expect(world.playerPosition == pit)
    }
}
