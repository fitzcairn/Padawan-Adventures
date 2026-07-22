import Foundation

nonisolated enum DefeatRules {
    /// Enemy contact defeats the player when energy is already zero.
    static func isDefeatedByEnemy(energy: Int) -> Bool {
        energy == 0
    }

    /// Pit contact defeats the player when health is already zero.
    static func isDefeatedByPit(health: Int) -> Bool {
        health == 0
    }
}
