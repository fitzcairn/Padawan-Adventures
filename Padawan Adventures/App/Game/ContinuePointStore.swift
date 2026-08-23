import Foundation

/// In-memory last-safe world snapshot used to restore after defeat.
nonisolated struct ContinuePointStore: Sendable {
    private(set) var snapshot: GameWorld

    init(world: GameWorld) {
        snapshot = world
    }

    /// Captures only when the world is still progressable after defeat restore.
    mutating func capture(_ world: GameWorld) {
        guard Self.isProgressable(world) else { return }
        snapshot = world
    }

    /// Captures only when a move settled without opening an encounter this tick
    /// and the resulting world is still progressable.
    mutating func captureIfSafe(_ world: GameWorld, tick: SimulationTickResult) {
        guard tick.shouldPersist else { return }
        guard !tick.hasEncounterContact else { return }
        capture(world)
    }

    /// False when restoring here would leave the player with no way to progress
    /// (e.g. zero energy while an enemy can already see/contact them).
    static func isProgressable(_ world: GameWorld) -> Bool {
        guard EnergyMechanic.isEnabled else { return true }
        guard let playerPosition = world.playerPosition else { return true }
        guard DefeatRules.isDefeatedByEnemy(energy: world.energyCount) else { return true }

        let threatened = world.entities.contains { entity in
            guard entity.isEnemy else { return false }
            return LineOfSight.canSee(
                from: entity.position,
                to: playerPosition,
                in: world
            )
        }
        return !threatened
    }
}

extension SimulationTickResult {
    /// True when this tick raised pit/enemy/gate contact.
    nonisolated var hasEncounterContact: Bool {
        didEnterPit
            || enemyContactID != nil
            || gateCoord != nil
            || merchantContactID != nil
    }

    /// True when a settled move should update the on-disk Continue save.
    /// Open encounters are excluded so Continue never resumes mid-fight / mid-hazard.
    nonisolated var shouldPersistContinueSave: Bool {
        shouldPersist && !hasEncounterContact
    }
}
