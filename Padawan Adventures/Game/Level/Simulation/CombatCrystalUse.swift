import Foundation

/// Maps merchant crystal wares to combat swing clips on `player.combat_sprite`.
nonisolated enum CombatCrystalUse {
    static let defaultSwing = "swing"
    static let purpleItemID = "merchant-ware-crystal-purple"
    static let yellowItemID = "merchant-ware-crystal-yellow"
    static let purpleSwing = "swing_purple"
    static let yellowSwing = "swing_yellow"

    static let knownSwings: Set<String> = [defaultSwing, purpleSwing, yellowSwing]

    static func swingAnimation(for itemID: String) -> String? {
        switch itemID {
        case purpleItemID: return purpleSwing
        case yellowItemID: return yellowSwing
        default: return nil
        }
    }

    static func resolvedSwing(_ stored: String?) -> String {
        guard let stored, knownSwings.contains(stored) else { return defaultSwing }
        return stored
    }

    /// Combat library config with `swing` pointing at the equipped crystal sheet.
    static func combatSprite(from config: SpriteConfig?, swing: String) -> SpriteConfig? {
        guard var config else { return nil }
        let key = resolvedSwing(swing)
        guard let source = config.animations[key] else { return config }
        config.animations = [defaultSwing: source]
        return config
    }
}
