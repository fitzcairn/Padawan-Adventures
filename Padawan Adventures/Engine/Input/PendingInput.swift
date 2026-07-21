import Foundation

struct PendingInput: Sendable {
    private(set) var destination: GridCoord?

    mutating func enqueue(_ coord: GridCoord) {
        destination = coord
    }

    mutating func consume() -> GridCoord? {
        defer { destination = nil }
        return destination
    }
}
