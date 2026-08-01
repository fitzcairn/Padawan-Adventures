import Foundation

nonisolated struct GeneratedRoom: Equatable, Sendable {
    let id: Int
    let cells: Set<GridCoord>
    let center: GridCoord
    /// Lattice coordinates used for packed-room adjacency.
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
