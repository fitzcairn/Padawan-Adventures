import Foundation
import Testing
@testable import Padawan_Adventures

struct CombatCrystalUseTests {
    @Test func mapsPurpleAndYellowWaresToSwingClips() {
        #expect(
            CombatCrystalUse.swingAnimation(for: CombatCrystalUse.purpleItemID)
                == CombatCrystalUse.purpleSwing
        )
        #expect(
            CombatCrystalUse.swingAnimation(for: CombatCrystalUse.yellowItemID)
                == CombatCrystalUse.yellowSwing
        )
        #expect(
            CombatCrystalUse.swingAnimation(for: CombatCrystalUse.doubleSaberItemID)
                == CombatCrystalUse.doubleSwing
        )
        #expect(
            CombatCrystalUse.swingAnimation(for: CombatCrystalUse.greenItemID)
                == CombatCrystalUse.greenSwing
        )
        #expect(CombatCrystalUse.swingAnimation(for: JetpackGateUse.itemID) == nil)
    }

    @Test func resolvedSwingFallsBackToDefault() {
        #expect(CombatCrystalUse.resolvedSwing(nil) == CombatCrystalUse.defaultSwing)
        #expect(CombatCrystalUse.resolvedSwing("nope") == CombatCrystalUse.defaultSwing)
        #expect(
            CombatCrystalUse.resolvedSwing(CombatCrystalUse.purpleSwing)
                == CombatCrystalUse.purpleSwing
        )
        #expect(
            CombatCrystalUse.resolvedSwing(CombatCrystalUse.doubleSwing)
                == CombatCrystalUse.doubleSwing
        )
        #expect(
            CombatCrystalUse.resolvedSwing(CombatCrystalUse.greenSwing)
                == CombatCrystalUse.greenSwing
        )
    }

    @Test func remapsCombatConfigSwingToEquippedSheet() {
        let purple = SpriteAnimationSource.sheet(
            sheet: "swing_purple_blade_up-spritesheet",
            atlas: "swing_purple_blade_up-atlas"
        )
        let config = SpriteConfig(
            root: "Sprites/Combat",
            animations: [
                CombatCrystalUse.defaultSwing: .sheet(
                    sheet: "player-combat-spritesheet",
                    atlas: "player-combat-atlas"
                ),
                CombatCrystalUse.purpleSwing: purple,
            ]
        )
        let remapped = CombatCrystalUse.combatSprite(from: config, swing: CombatCrystalUse.purpleSwing)
        #expect(remapped?.animations[CombatCrystalUse.defaultSwing] == purple)
        #expect(remapped?.animations[CombatCrystalUse.purpleSwing] == nil)
    }

    @Test func bundledCombatSpriteIncludesCrystalSwings() throws {
        let config = try PlayerConfig.loadFromBundle()
        #expect(config.combatSprite?.animations[CombatCrystalUse.defaultSwing] != nil)
        #expect(config.combatSprite?.animations[CombatCrystalUse.purpleSwing] != nil)
        #expect(config.combatSprite?.animations[CombatCrystalUse.yellowSwing] != nil)
        #expect(config.combatSprite?.animations[CombatCrystalUse.doubleSwing] != nil)
        #expect(config.combatSprite?.animations[CombatCrystalUse.greenSwing] != nil)
    }
}

struct CombatSwingPersistenceTests {
    @Test func combatSwingSurvivesPlistRoundTrip() throws {
        var state = PlayerGameState(health: 3, energy: 2)
        state.combatSwingAnimation = CombatCrystalUse.purpleSwing
        let data = try PropertyListEncoder().encode(state)
        let decoded = try PropertyListDecoder().decode(PlayerGameState.self, from: data)
        #expect(decoded.combatSwingAnimation == CombatCrystalUse.purpleSwing)
    }

    @Test func resetForNewGameClearsCombatSwing() {
        var state = PlayerGameState(
            health: 3,
            energy: 2,
            combatSwingAnimation: CombatCrystalUse.yellowSwing
        )
        state.resetForNewGame(health: 5, energy: 4)
        #expect(state.combatSwingAnimation == nil)
    }

    @Test func missingCombatSwingDecodesAsNil() throws {
        let data = try JSONEncoder().encode(PlayerGameState(health: 3, energy: 2))
        let decoded = try JSONDecoder().decode(PlayerGameState.self, from: data)
        #expect(decoded.combatSwingAnimation == nil)
    }
}
