import CoreGraphics
import Testing
import UIKit
@testable import Padawan_Adventures

struct EnemyConfigTests {
    @Test func decodesNamedTypes() throws {
        let yaml = """
        enemies:
          spider:
            letter: E
            color: "#FF0000"
            tiles_per_second: 1.0
            forget_seconds: 3.0
            combat_timer_seconds: 10
            shot_travel_seconds: 1.5
            stars_to_win: 10
            shot_letters: [a, b, c]
            fx:
              notice: enemy-spider
          scout:
            letter: S
            color: "#00FF00"
            tiles_per_second: 2.0
            forget_seconds: 1.5
            shot_letters: [a]
        """

        let config = try EnemyConfig.decode(from: yaml)
        #expect(config.slashMaxSeconds == EnemyConfig.fallbackSlashMaxSeconds)
        #expect(config.slashMaxScreenWidthFraction == EnemyConfig.fallbackSlashMaxScreenWidthFraction)
        #expect(config.enemies.count == 2)
        #expect(config.type(named: "spider")?.letter == "E")
        #expect(config.type(named: "spider")?.color == "#FF0000")
        #expect(config.type(named: "spider")?.tilesPerSecond == 1.0)
        #expect(config.type(named: "spider")?.forgetSeconds == 3.0)
        #expect(config.type(named: "spider")?.combatTimerSeconds == 10)
        #expect(config.type(named: "spider")?.shotTravelSeconds == 1.5)
        #expect(config.type(named: "spider")?.starsToWin == 10)
        #expect(config.type(named: "spider")?.fx.trackID(for: "notice") == "enemy-spider")
        #expect(config.type(named: "spider")?.shotTypes["A"]?.fx.trackID(for: "shoot") == "sfx_letter_a_name")
        #expect(config.type(named: "spider")?.shotTypes["B"]?.fx.trackID(for: "shoot") == "sfx_letter_b_name")
        #expect(config.type(named: "spider")?.shotTypes["C"]?.fx.trackID(for: "shoot") == "sfx_letter_c_name")
        #expect(config.type(named: "scout")?.letter == "S")
        #expect(config.type(named: "scout")?.combatTimerSeconds == 10)
        #expect(config.type(named: "scout")?.starsToWin == 10)
        #expect(config.type(named: "scout")?.fx == .empty)
        #expect(config.type(named: "scout")?.shotTypes["A"]?.fx.trackID(for: "shoot") == "sfx_letter_a_name")
        try config.validate()
    }

    @Test func fallbackMatchesSpiderDefaults() {
        let config = EnemyConfig.fallback
        #expect(config.slashMaxSeconds == 0.5)
        #expect(config.slashMaxScreenWidthFraction == 0.20)
        let spider = config.type(named: "spider")
        #expect(spider?.letter == "E")
        #expect(spider?.color == "#FF0000")
        #expect(spider?.tilesPerSecond == 1.0)
        #expect(spider?.forgetSeconds == 3.0)
        #expect(spider?.combatTimerSeconds == 10)
        #expect(spider?.shotTravelSeconds == 3.2)
        #expect(spider?.starsToWin == 10)
        #expect(spider?.shotLetters == ["A", "B", "C"])
    }

    @Test func decodesSlashMaxSeconds() throws {
        let yaml = """
        slash_max_seconds: 0.75
        enemies:
          spider:
            letter: E
            color: "#FF0000"
            tiles_per_second: 1.0
            forget_seconds: 3.0
            shot_letters: [a]
        """
        let config = try EnemyConfig.decode(from: yaml)
        #expect(config.slashMaxSeconds == 0.75)
    }

    @Test func decodesSlashMaxScreenWidthFraction() throws {
        let yaml = """
        slash_max_screen_width_fraction: 0.12
        enemies:
          spider:
            letter: E
            color: "#FF0000"
            tiles_per_second: 1.0
            forget_seconds: 3.0
            shot_letters: [a]
        """
        let config = try EnemyConfig.decode(from: yaml)
        #expect(config.slashMaxScreenWidthFraction == 0.12)
    }

    @Test func appliesDefaultsToEmptyEntries() throws {
        let yaml = """
        slash_max_seconds: 0.5
        defaults:
          letter: E
          color: "#FF0000"
          tiles_per_second: 0.5
          forget_seconds: 3.0
          combat_timer_seconds: 30
          shot_travel_seconds: 8
          stars_to_win: 5
          shot_letters: [a, b, c]
          fx:
            notice: enemy-spider
        enemies:
          spider:
          scout:
            letter: S
            tiles_per_second: 2.0
        """
        let config = try EnemyConfig.decode(from: yaml)
        #expect(config.type(named: "spider")?.combatTimerSeconds == 30)
        #expect(config.type(named: "spider")?.shotTypes["A"]?.fx.trackID(for: "shoot") == "sfx_letter_a_name")
        #expect(config.type(named: "scout")?.letter == "S")
        #expect(config.type(named: "scout")?.tilesPerSecond == 2.0)
        #expect(config.type(named: "scout")?.starsToWin == 5)
    }

    @Test func validateRejectsNonPositiveSlashMaxSeconds() {
        var config = EnemyConfig.fallback
        config.slashMaxSeconds = 0
        #expect(throws: EnemyConfigError.invalid("slash_max_seconds must be > 0")) {
            try config.validate()
        }
    }

    @Test func validateRejectsInvalidSlashMaxScreenWidthFraction() {
        var config = EnemyConfig.fallback
        config.slashMaxScreenWidthFraction = 0
        #expect(throws: EnemyConfigError.invalid(
            "slash_max_screen_width_fraction must be in (0, 1]"
        )) {
            try config.validate()
        }
        config = EnemyConfig.fallback
        config.slashMaxScreenWidthFraction = 1.5
        #expect(throws: EnemyConfigError.invalid(
            "slash_max_screen_width_fraction must be in (0, 1]"
        )) {
            try config.validate()
        }
    }

    @Test func loadsSlashMaxSecondsFromBundle() throws {
        let config = try EnemyConfig.loadFromBundle()
        #expect(config.slashMaxSeconds == 0.5)
        #expect(config.slashMaxScreenWidthFraction == 0.20)
        #expect(config.type(named: "grunt") == nil)
        #expect(config.type(named: "spider") != nil)
        #expect(config.enemies.count == 10)
        #expect(config.type(named: "spider")?.shotTypes["A"]?.fx.trackID(for: "shoot") == "sfx_letter_a_name")
        #expect(config.type(named: "spider")?.combatTimerSeconds == 30)
    }

    @Test func decodesSpritesMapAndResolvesTypeSprite() throws {
        let yaml = """
        sprites:
          spider:
            root: Enemies/Spider
            trim: false
            scale: 0.60
            animations:
              idle_down: { sheet: spider-idle_down-spritesheet, atlas: spider-idle_down-atlas }
        defaults:
          letter: E
          color: "#FF0000"
          tiles_per_second: 0.5
          forget_seconds: 3.0
          shot_letters: [a]
        enemies:
          spider: { sprite: spider }
        """
        let config = try EnemyConfig.decode(from: yaml)
        let resolved = try #require(config.spriteConfig(for: "spider"))
        #expect(resolved.id == "spider")
        #expect(resolved.config.root == "Enemies/Spider")
        #expect(resolved.config.trim == false)
        #expect(resolved.config.scale == 0.60)
        #expect(config.type(named: "spider")?.sprite == "spider")
    }

    @Test func validateRejectsUnknownSpriteReference() {
        var config = EnemyConfig.fallback
        config.enemies["spider"]?.sprite = "missing"
        #expect(throws: EnemyConfigError.invalid("spider.sprite references unknown sprite 'missing'")) {
            try config.validate()
        }
    }

    @Test func typeBlockOverridesDefaultsWhenSpritesPresent() throws {
        let yaml = """
        sprites:
          dino:
            root: Enemies/Dino
            trim: false
            scale: 1.10
            animations:
              idle_down: { sheet: dino-idle_down-spritesheet, atlas: dino-idle_down-atlas }
        defaults:
          letter: E
          color: "#FF0000"
          tiles_per_second: 0.5
          forget_seconds: 3.0
          combat_timer_seconds: 30
          stars_to_win: 5
          shot_letters: [a, b, c]
        enemies:
          dino:
            sprite: dino
            tiles_per_second: 0.35
        """
        let config = try EnemyConfig.decode(from: yaml)
        let dino = try #require(config.type(named: "dino"))
        #expect(dino.tilesPerSecond == 0.35)
        #expect(dino.forgetSeconds == 3.0)
        #expect(dino.combatTimerSeconds == 30)
        #expect(dino.starsToWin == 5)
        #expect(dino.sprite == "dino")
    }

    @Test func bundleExposesTenSpriteBackedEnemyTypes() throws {
        let config = try EnemyConfig.loadFromBundle()
        let expectedIDs = [
            "centipede", "dino", "drone", "ice_monster", "lava_lizard",
            "moth", "robot", "snake", "spider", "treant",
        ]
        #expect(Set(config.sprites.keys) == Set(expectedIDs))
        #expect(Set(config.enemies.keys) == Set(expectedIDs))

        for id in expectedIDs {
            let sprite = try #require(config.sprites[id])
            #expect(sprite.root.hasPrefix("Sprites/Enemies/"))
            #expect(sprite.trim == false)
            #expect(sprite.chromaKey == nil)
            for locomotion in [SpriteLocomotion.idle, .walk] {
                for direction in CompassDirection.allCases {
                    let name = direction.animationName(locomotion: locomotion)
                    #expect(sprite.animations[name] != nil, "\(id) missing \(name)")
                }
            }
            let resolved = try #require(config.spriteConfig(for: id))
            #expect(resolved.id == id)
        }
    }

    @Test func everyLevelEnemyTypeExistsInCatalog() throws {
        let enemies = try EnemyConfig.loadFromBundle()
        let levels = LevelCatalog.loadFromBundle()
        #expect(!levels.isEmpty)
        for descriptor in levels {
            let level = try LevelConfig.loadFromBundle(
                named: descriptor.resourceName,
                subdirectory: LevelCatalog.subdirectory
            )
            let types = level.enemies?.types ?? []
            #expect(!types.isEmpty, "\(descriptor.resourceName) has no enemies.types")
            for typeID in types {
                #expect(
                    enemies.enemies[typeID] != nil,
                    "\(descriptor.resourceName) references unknown enemy '\(typeID)'"
                )
            }
        }
    }

    @Test func validateRejectsEmptyShotTypes() {
        var config = EnemyConfig.fallback
        config.enemies["spider"]?.shotTypes = [:]
        #expect(throws: EnemyConfigError.invalid("spider.shot_types must not be empty")) {
            try config.validate()
        }
    }

    @Test func validateRejectsShotTypeMissingFx() {
        var config = EnemyConfig.fallback
        config.enemies["spider"]?.shotTypes["A"] = EnemyShotTypeConfig(fx: .empty)
        #expect(throws: EnemyConfigError.invalid("spider.shot_types.A.fx must name a shoot track")) {
            try config.validate()
        }
    }

    @Test func validateRejectsNonPositiveCombatTimer() {
        var config = EnemyConfig.fallback
        config.enemies["spider"]?.combatTimerSeconds = 0
        #expect(throws: EnemyConfigError.invalid("spider.combat_timer_seconds must be > 0")) {
            try config.validate()
        }
    }

    @Test func validateRejectsInvalidStarsToWin() {
        var config = EnemyConfig.fallback
        config.enemies["spider"]?.starsToWin = 0
        #expect(throws: EnemyConfigError.invalid("spider.stars_to_win must be >= 1")) {
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
        config.enemies["spider"]?.color = "red"
        #expect(throws: EnemyConfigError.invalid("spider.color must be a hex color like #RRGGBB")) {
            try config.validate()
        }
    }

    @Test func validateRejectsNonPositiveSpeed() {
        var config = EnemyConfig.fallback
        config.enemies["spider"]?.tilesPerSecond = 0
        #expect(throws: EnemyConfigError.invalid("spider.tiles_per_second must be > 0")) {
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
