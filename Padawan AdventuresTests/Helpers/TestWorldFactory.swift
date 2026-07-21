import Testing
@testable import Padawan_Adventures

enum TestWorldFactory {
    static func emptyFloor(width: Int, height: Int, stories: Int = 1) -> GameWorld {
        let floor = Tile(kind: .floor(isPit: false))
        let tiles = Array(
            repeating: Array(repeating: Array(repeating: floor, count: width), count: height),
            count: stories
        )
        let spawn = GridCoord(x: 0, y: 0, story: 0)
        let player = GameEntity(letter: "P", position: spawn, isPlayer: true)
        return GameWorld(width: width, height: height, storyCount: stories, tiles: tiles, entities: [player], spawn: spawn)
    }

    static func withTiles(_ tiles: [[[Tile]]], spawn: GridCoord) -> GameWorld {
        let stories = tiles.count
        let height = tiles[0].count
        let width = tiles[0][0].count
        let player = GameEntity(letter: "P", position: spawn, isPlayer: true)
        return GameWorld(width: width, height: height, storyCount: stories, tiles: tiles, entities: [player], spawn: spawn)
    }
}
