import CoreGraphics
import Foundation
import Testing
@testable import Padawan_Adventures

struct AppConfigTests {
    @Test func decodesSampleYAML() throws {
        let yaml = """
        version: 1
        seed: 42
        world:
          stories: 1
        """

        let config = try WorldLoader.decodeConfig(from: yaml)
        #expect(config.version == 1)
        #expect(config.seed == 42)
        #expect(config.resolvedSeed() == 42)
        #expect(config.world.stories == 1)
        #expect(config.display.tileWidth == 40)
        #expect(config.display.tileHeight == 40)
        #expect(config.dadModePassword == AppConfig.defaultDadModePassword)
        try config.validate()
    }

    @Test func decodesDadModePassword() throws {
        let yaml = """
        version: 1
        seed: 1
        dad_mode_password: "9876"
        world:
          stories: 1
        """
        let config = try WorldLoader.decodeConfig(from: yaml)
        #expect(config.dadModePassword == "9876")
        try config.validate()
    }

    @Test func dadModePasswordDefaultsWhenOmitted() throws {
        let yaml = """
        version: 1
        seed: 1
        world:
          stories: 1
        """
        let config = try WorldLoader.decodeConfig(from: yaml)
        #expect(config.dadModePassword == AppConfig.defaultDadModePassword)
    }

    @Test func decodesUnquotedDadModePasswordAsDigits() throws {
        let yaml = """
        version: 1
        seed: 1
        dad_mode_password: 1234
        world:
          stories: 1
        """
        let config = try WorldLoader.decodeConfig(from: yaml)
        #expect(config.dadModePassword == "1234")
    }

    @Test func bundledAppConfigIncludesDadModePassword() throws {
        let config = try WorldLoader.loadConfigFromBundle()
        #expect(config.dadModePassword == "1234")
        #expect(DadModePassword.matches(entered: "1234", expected: config.dadModePassword))
        #expect(!DadModePassword.matches(entered: "0000", expected: config.dadModePassword))
    }

    @Test func decodesTimeSeedToken() throws {
        let yaml = """
        version: 1
        seed: time
        world:
          stories: 1
        """
        let config = try WorldLoader.decodeConfig(from: yaml)
        #expect(config.seed == nil)
        let date = Date(timeIntervalSince1970: 1_700_000_000.5)
        #expect(config.resolvedSeed(at: date) == 1_700_000_000_500)
        try config.validate()
    }

    @Test func decodesDisplayTileSize() throws {
        let yaml = """
        version: 1
        seed: 1
        world:
          stories: 1
        display:
          tile_width: 48
          tile_height: 24
          wall_height: 36
        """

        let config = try WorldLoader.decodeConfig(from: yaml)
        #expect(config.display.tileWidth == 48)
        #expect(config.display.tileHeight == 24)
        #expect(config.display.overlayDismissSeconds == 6)
        let iso = config.display.makeIsometricConfig()
        #expect(iso.tileWidth == 48 as CGFloat)
        #expect(iso.tileHeight == 24 as CGFloat)
        #expect(iso.wallHeight == 36 as CGFloat)
        #expect(iso.storyHeight == 48 as CGFloat)
    }

    @Test func decodesOverlayDismissSeconds() throws {
        let yaml = """
        version: 1
        seed: 1
        world:
          stories: 1
        display:
          tile_width: 48
          tile_height: 24
          overlay_dismiss_seconds: 3.5
        """

        let config = try WorldLoader.decodeConfig(from: yaml)
        #expect(config.display.overlayDismissSeconds == 3.5)
    }

    @Test func rejectsInvalidStoryCount() throws {
        let yaml = """
        version: 1
        seed: 1
        world:
          stories: 2
        """

        let config = try WorldLoader.decodeConfig(from: yaml)
        #expect(throws: WorldSeedError.invalidStoryCount(2)) {
            try config.validate()
        }
    }

    @Test func composeUsesLevelMapSizeAndAppStories() throws {
        let app = try WorldLoader.decodeConfig(from: """
        version: 1
        seed: 1
        world:
          stories: 1
        """)
        let level = try LevelConfig.decode(from: """
        name: Level Override
        width: 30
        height: 40
        algorithm: rooms_doors
        room_count: 3
        corridor_width: 2
        room:
          min_room_size: 4
          max_room_size: 8
          pit_chance: 0
          partition_gate_chance: 0
        gate:
          fx: { opened: sfx_gate_opened_alt }
          minigames:
            - type: spelling
              num_padding_letters: 2
        """)
        let generation = WorldGenerationConfig.compose(app: app, level: level)
        #expect(generation.world.width == 30)
        #expect(generation.world.height == 40)
        #expect(generation.world.stories == 1)
        #expect(level.worldFx.trackID(for: "gate_opened") == "sfx_gate_opened_alt")
    }

    @Test func composeUsesFallbackLevelWorldFx() throws {
        let app = AppConfig(version: 1, seed: 1, world: .init(stories: 1))
        let level = LevelConfig.fallback
        let generation = WorldGenerationConfig.compose(app: app, level: level)
        #expect(level.worldFx.trackID(for: "gate_opened") == "gate-open")
        #expect(generation.enemies?.type == "spider")
        #expect(generation.enemies?.spawnChancePerRoom == 0.8)
    }
}
