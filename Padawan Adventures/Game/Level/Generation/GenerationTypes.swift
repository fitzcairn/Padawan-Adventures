import Foundation

nonisolated struct GeneratedRoom: Equatable, Sendable {
    let id: Int
    let cells: Set<GridCoord>
    let center: GridCoord
    /// Reserved for packed-room adjacency; always 0 in the current rooms_doors algorithm.
    let latticeX: Int
    let latticeY: Int
}

nonisolated struct GenerationResult: Sendable {
    let world: GameWorld
    let rooms: [GeneratedRoom]
    let topRightRoomID: Int
    let joinPairs: [(Int, Int)]
}

struct RoomPair: Hashable {
    let low: Int
    let high: Int
    init(_ a: Int, _ b: Int) {
        low = min(a, b)
        high = max(a, b)
    }
}

/// Mutable workspace threaded through each generation pass in deterministic order.
struct GenerationAttemptState {
    var rng: SeededGenerator
    var tiles: [[[Tile]]]
    var rooms: [GeneratedRoom]
    var entities: [GameEntity]
    var occupied: Set<GridCoord>
    var pickupCells: Set<GridCoord>
    var spawn: GridCoord
    var topRight: GeneratedRoom
    var joinEdges: [(Int, Int)]
    let width: Int
    let height: Int
    let stories: Int
}

/// Fixed-order generation phases; RNG call sequence must match legacy `generateAttempt`.
enum GenerationPass: Int, CaseIterable {
    case rooms = 1
    case gates = 2
    case pits = 3
    case entities = 4
    case finalize = 5

    var phaseIndex: Double { Double(rawValue) }
}
