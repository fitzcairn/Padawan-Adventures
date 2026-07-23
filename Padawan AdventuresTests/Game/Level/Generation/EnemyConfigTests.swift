import CoreGraphics
import Testing
import UIKit
@testable import Padawan_Adventures

struct EnemyConfigTests {
    @Test func decodesNamedTypes() throws {
        let yaml = """
        enemies:
          grunt:
            letter: E
            color: "#FF0000"
            tiles_per_second: 1.0
            forget_seconds: 3.0
            combat_timer_seconds: 10
            shot_travel_seconds: 1.5
            stars_to_win: 10
            shot_types:
              A:
                fx: sfx_letter_a_name
              B:
                fx: sfx_letter_b_name
              C:
                fx: sfx_letter_c_name
            fx:
              contact: sfx_enemy_contact
          scout:
            letter: S
            color: "#00FF00"
            tiles_per_second: 2.0
            forget_seconds: 1.5
            shot_types:
              X:
                fx: sfx_letter_a_name
        """

        let config = try EnemyConfig.decode(from: yaml)
        #expect(config.slashMaxSeconds == EnemyConfig.fallbackSlashMaxSeconds)
        #expect(config.enemies.count == 2)
        #expect(config.type(named: "grunt")?.letter == "E")
        #expect(config.type(named: "grunt")?.color == "#FF0000")
        #expect(config.type(named: "grunt")?.tilesPerSecond == 1.0)
        #expect(config.type(named: "grunt")?.forgetSeconds == 3.0)
        #expect(config.type(named: "grunt")?.combatTimerSeconds == 10)
        #expect(config.type(named: "grunt")?.shotTravelSeconds == 1.5)
        #expect(config.type(named: "grunt")?.starsToWin == 10)
        #expect(config.type(named: "grunt")?.fx.trackID(for: "contact") == "sfx_enemy_contact")
        #expect(config.type(named: "grunt")?.shotTypes["A"]?.fx.trackID(for: "shoot") == "sfx_letter_a_name")
        #expect(config.type(named: "grunt")?.shotTypes["B"]?.fx.trackID(for: "shoot") == "sfx_letter_b_name")
        #expect(config.type(named: "grunt")?.shotTypes["C"]?.fx.trackID(for: "shoot") == "sfx_letter_c_name")
        #expect(config.type(named: "scout")?.letter == "S")
        #expect(config.type(named: "scout")?.combatTimerSeconds == 10)
        #expect(config.type(named: "scout")?.starsToWin == 10)
        #expect(config.type(named: "scout")?.fx == .empty)
        #expect(config.type(named: "scout")?.shotTypes["X"]?.fx.trackID(for: "shoot") == "sfx_letter_a_name")
        try config.validate()
    }

    @Test func fallbackMatchesGruntDefaults() {
        let config = EnemyConfig.fallback
        #expect(config.slashMaxSeconds == 0.5)
        let grunt = config.type(named: "grunt")
        #expect(grunt?.letter == "E")
        #expect(grunt?.color == "#FF0000")
        #expect(grunt?.tilesPerSecond == 1.0)
        #expect(grunt?.forgetSeconds == 3.0)
        #expect(grunt?.combatTimerSeconds == 10)
        #expect(grunt?.shotTravelSeconds == 3.2)
        #expect(grunt?.starsToWin == 10)
        #expect(grunt?.shotLetters == ["A", "B", "C"])
    }

    @Test func decodesSlashMaxSeconds() throws {
        let yaml = """
        slash_max_seconds: 0.75
        enemies:
          grunt:
            letter: E
            color: "#FF0000"
            tiles_per_second: 1.0
            forget_seconds: 3.0
            shot_types:
              A:
                fx: sfx_letter_a_name
        """
        let config = try EnemyConfig.decode(from: yaml)
        #expect(config.slashMaxSeconds == 0.75)
    }

    @Test func validateRejectsNonPositiveSlashMaxSeconds() {
        var config = EnemyConfig.fallback
        config.slashMaxSeconds = 0
        #expect(throws: EnemyConfigError.invalid("slash_max_seconds must be > 0")) {
            try config.validate()
        }
    }

    @Test func loadsSlashMaxSecondsFromBundle() throws {
        let config = try EnemyConfig.loadFromBundle()
        #expect(config.slashMaxSeconds == 0.5)
    }

    @Test func validateRejectsEmptyShotTypes() {
        var config = EnemyConfig.fallback
        config.enemies["grunt"]?.shotTypes = [:]
        #expect(throws: EnemyConfigError.invalid("grunt.shot_types must not be empty")) {
            try config.validate()
        }
    }

    @Test func validateRejectsShotTypeMissingFx() {
        var config = EnemyConfig.fallback
        config.enemies["grunt"]?.shotTypes["A"] = EnemyShotTypeConfig(fx: .empty)
        #expect(throws: EnemyConfigError.invalid("grunt.shot_types.A.fx must name a shoot track")) {
            try config.validate()
        }
    }

    @Test func validateRejectsNonPositiveCombatTimer() {
        var config = EnemyConfig.fallback
        config.enemies["grunt"]?.combatTimerSeconds = 0
        #expect(throws: EnemyConfigError.invalid("grunt.combat_timer_seconds must be > 0")) {
            try config.validate()
        }
    }

    @Test func validateRejectsInvalidStarsToWin() {
        var config = EnemyConfig.fallback
        config.enemies["grunt"]?.starsToWin = 0
        #expect(throws: EnemyConfigError.invalid("grunt.stars_to_win must be >= 1")) {
            try config.validate()
        }
    }

    @Test func validateRejectsEmptyEnemies() {
        let config = EnemyConfig(enemies: [:])
        #expect(throws: EnemyConfigError.invalid("enemies must not be empty")) {
            try config.validate()
        }
    }

    @Test func validateRejectsBadColor() {
        var config = EnemyConfig.fallback
        config.enemies["grunt"]?.color = "red"
        #expect(throws: EnemyConfigError.invalid("grunt.color must be a hex color like #RRGGBB")) {
            try config.validate()
        }
    }

    @Test func validateRejectsNonPositiveSpeed() {
        var config = EnemyConfig.fallback
        config.enemies["grunt"]?.tilesPerSecond = 0
        #expect(throws: EnemyConfigError.invalid("grunt.tiles_per_second must be > 0")) {
            try config.validate()
        }
    }

    @Test func decodeFailsOnInvalidYAML() {
        #expect(throws: EnemyConfigError.decodeFailed) {
            try EnemyConfig.decode(from: "enemies: [not, valid]")
        }
    }

    @Test func fillColorParsesHex() {
        let type = EnemyTypeConfig(
            letter: "E",
            color: "#FF0000",
            tilesPerSecond: 1,
            forgetSeconds: 3
        )
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        type.fillColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 1) < 0.001)
        #expect(abs(g) < 0.001)
        #expect(abs(b) < 0.001)
    }
}
