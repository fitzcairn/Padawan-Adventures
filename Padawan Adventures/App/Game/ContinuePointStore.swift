import Foundation

/// In-memory last-safe world snapshot used to restore after defeat.
nonisolated struct ContinuePointStore: Sendable {
    private(set) var snapshot: GameWorld

    init(world: GameWorld) {
        snapshot = world
    }

    mutating func capture(_ world: GameWorld) {
        snapshot = world
    }

    /// Captures only when a move settled without opening an encounter this tick.
    mutating func captureIfSafe(_ world: GameWorld, tick: SimulationTickResult) {
        guard tick.shouldPersist else { return }
        guard !tick.hasEncounterContact else { return }
        snapshot = world
    }
}

extension SimulationTickResult {
    /// True when this tick raised pit/enemy/boom/gate contact.
    var hasEncounterContact: Bool {
        didEnterPit
            || enemyContactID != nil
            || boomCoord != nil
            || gateCoord != nil
    }
}
