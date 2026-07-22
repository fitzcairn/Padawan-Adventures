import CoreGraphics
import Testing
import UIKit
@testable import Padawan_Adventures

struct EnemyConfigTests {
    @Test func decodesNamedTypes() throws {
        let yaml = """
        types:
          grunt:
            letter: E
            color: "#FF0000"
            tiles_per_second: 1.0
            forget_seconds: 3.0
            fx:
              contact: sfx_enemy_contact
          scout:
            letter: S
            color: "#00FF00"
            tiles_per_second: 2.0
            forget_seconds: 1.5
        """

        let config = try EnemyConfig.decode(from: yaml)
        #expect(config.types.count == 2)
        #expect(config.type(named: "grunt")?.letter == "E")
        #expect(config.type(named: "grunt")?.color == "#FF0000")
        #expect(config.type(named: "grunt")?.tilesPerSecond == 1.0)
        #expect(config.type(named: "grunt")?.forgetSeconds == 3.0)
        #expect(config.type(named: "grunt")?.fx.trackID(for: "contact") == "sfx_enemy_contact")
        #expect(config.type(named: "scout")?.letter == "S")
        #expect(config.type(named: "scout")?.fx == .empty)
        try config.validate()
    }

    @Test func fallbackMatchesGruntDefaults() {
        let config = EnemyConfig.fallback
        let grunt = config.type(named: "grunt")
        #expect(grunt?.letter == "E")
        #expect(grunt?.color == "#FF0000")
        #expect(grunt?.tilesPerSecond == 1.0)
        #expect(grunt?.forgetSeconds == 3.0)
    }

    @Test func validateRejectsEmptyTypes() {
        let config = EnemyConfig(types: [:])
        #expect(throws: EnemyConfigError.invalid("types must not be empty")) {
            try config.validate()
        }
    }

    @Test func validateRejectsBadColor() {
        var config = EnemyConfig.fallback
        config.types["grunt"]?.color = "red"
        #expect(throws: EnemyConfigError.invalid("grunt.color must be a hex color like #RRGGBB")) {
            try config.validate()
        }
    }

    @Test func validateRejectsNonPositiveSpeed() {
        var config = EnemyConfig.fallback
        config.types["grunt"]?.tilesPerSecond = 0
        #expect(throws: EnemyConfigError.invalid("grunt.tiles_per_second must be > 0")) {
            try config.validate()
        }
    }

    @Test func decodeFailsOnInvalidYAML() {
        #expect(throws: EnemyConfigError.decodeFailed) {
            try EnemyConfig.decode(from: "types: [not, valid]")
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
