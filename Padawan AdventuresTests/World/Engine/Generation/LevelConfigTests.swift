import Testing
@testable import Padawan_Adventures

struct LevelConfigTests {
    private static let baseLevelYAML = """
        name: Level
        music: level_theme
        width: 100
        height: 100
        algorithm: rooms_doors
        room_count: 100
        corridor_width: 2
        room:
          min_room_size: 4
          max_room_size: 12
          pit_chance: 0.2
          pit_mean_size: 2
          pit_max_size: 5
          wall_destructible_chance: 0.8
          gate_chance: 0.5
        pickups:
          health:
            spawn_chance_per_room: 0.8
          energy:
            spawn_chance_per_room: 0.8
        """

    @Test func decodesLevelYAML() throws {
        let yaml = """
        name: Level 1
        width: 100
        height: 100
        algorithm: rooms_doors
        room_count: 100
        corridor_width: 2
        room:
          min_room_size: 4
          max_room_size: 12
          pit_chance: 0.2
          pit_mean_size: 2
          pit_max_size: 5
          wall_destructible_chance: 0.8
          gate_chance: 0.5
        pickups:
          health:
            spawn_chance_per_room: 0.8
          energy:
            spawn_chance_per_room: 0.8
        """
        let level = try LevelConfig.decode(from: yaml)
        #expect(level.name == "Level 1")
        #expect(level.width == 100)
        #expect(level.height == 100)
        #expect(level.algorithm == "rooms_doors")
        #expect(level.roomCount == 100)
        #expect(level.corridorWidth == 2)
        #expect(level.room.minRoomSize == 4)
        #expect(level.room.maxRoomSize == 12)
        #expect(level.room.pitChance == 0.2)
        #expect(level.room.pitMeanSize == 2)
        #expect(level.room.pitMaxSize == 5)
        #expect(level.room.wallDestructibleChance == 0.8)
        #expect(level.room.gateChance == 0.5)
        #expect(level.pickups?.health?.spawnChancePerRoom == 0.8)
        #expect(level.pickups?.energy?.spawnChancePerRoom == 0.8)
        #expect(level.music == nil)
        #expect(level.musicCue == .unchanged)
    }

    @Test func inheritsMusicFromBase() throws {
        let child = """
        inherits: base_level
        name: Level 1
        """
        let level = try LevelConfig.decode(
            from: child,
            parents: ["base_level": Self.baseLevelYAML]
        )
        #expect(level.music == "level_theme")
        #expect(level.musicCue == .track("level_theme"))
    }

    @Test func childCanOverrideMusic() throws {
        let child = """
        inherits: base_level
        name: Level 1
        music: silence
        """
        let level = try LevelConfig.decode(
            from: child,
            parents: ["base_level": Self.baseLevelYAML]
        )
        #expect(level.music == "silence")
        #expect(level.musicCue == .silence)
    }

    @Test func decodesFxDictionary() throws {
        let yaml = """
        name: Level 1
        width: 20
        height: 20
        algorithm: rooms_doors
        room_count: 4
        corridor_width: 2
        room:
          min_room_size: 4
          max_room_size: 8
          pit_chance: 0
          wall_destructible_chance: 0
          gate_chance: 0
        fx:
          wall_destroyed: sfx_wall_destroyed_alt
        """
        let level = try LevelConfig.decode(from: yaml)
        #expect(level.fx?.trackID(for: "wall_destroyed") == "sfx_wall_destroyed_alt")
    }

    @Test func childCanOverrideInheritedFxKeys() throws {
        let base = Self.baseLevelYAML + """
        
        fx:
          wall_destroyed: sfx_wall_destroyed
          gate_opened: sfx_gate_opened
        """
        let child = """
        inherits: base_level
        name: Level 1
        fx:
          wall_destroyed: sfx_wall_destroyed_alt
        """
        let level = try LevelConfig.decode(
            from: child,
            parents: ["base_level": base]
        )
        #expect(level.fx?.trackID(for: "wall_destroyed") == "sfx_wall_destroyed_alt")
        #expect(level.fx?.trackID(for: "gate_opened") == "sfx_gate_opened")
    }

    @Test func inheritsFromBaseAndOverridesFields() throws {
        let child = """
        inherits: base_level
        name: Level 2
        room_count: 50
        room:
          pit_chance: 0.9
        """
        let level = try LevelConfig.decode(
            from: child,
            parents: ["base_level": Self.baseLevelYAML]
        )
        #expect(level.name == "Level 2")
        #expect(level.width == 100)
        #expect(level.height == 100)
        #expect(level.roomCount == 50)
        #expect(level.corridorWidth == 2)
        #expect(level.room.pitChance == 0.9)
        #expect(level.room.minRoomSize == 4)
        #expect(level.room.maxRoomSize == 12)
        #expect(level.room.wallDestructibleChance == 0.8)
        #expect(level.pickups?.health?.spawnChancePerRoom == 0.8)
    }

    @Test func inheritanceRequiresParent() throws {
        let child = """
        inherits: missing_base
        name: Level 1
        """
        #expect(throws: WorldSeedError.missingResource) {
            try LevelConfig.decode(from: child, parents: [:])
        }
    }

    @Test func incompleteLevelWithoutInheritanceFailsDecode() throws {
        let yaml = """
        name: Level 1
        room_count: 10
        """
        #expect(throws: WorldSeedError.decodeFailed) {
            try LevelConfig.decode(from: yaml)
        }
    }

    @Test func worldYAMLAllowsMissingGenerationAndMapSize() throws {
        let yaml = """
        version: 1
        seed: time
        world:
          stories: 1
        enemies:
          type: grunt
          spawn_chance_per_room: 0.8
        """
        let config = try WorldLoader.decodeConfig(from: yaml)
        #expect(config.seed == nil)
        #expect(config.world.width == LevelConfig.fallback.width)
        #expect(config.world.height == LevelConfig.fallback.height)
        #expect(config.generation == LevelConfig.fallback.generation)
        try config.validate()
    }

    @Test func deepMergeNestedDictionariesPreferChild() {
        let base: [String: Any] = [
            "room": [
                "pit_chance": 0.2,
                "gate_chance": 0.5,
            ],
            "room_count": 100,
        ]
        let child: [String: Any] = [
            "room": [
                "pit_chance": 0.9,
            ],
            "name": "Level 3",
        ]
        let merged = LevelConfig.deepMerge(base, overwriting: child)
        #expect(merged["name"] as? String == "Level 3")
        #expect(merged["room_count"] as? Int == 100)
        let room = merged["room"] as? [String: Any]
        #expect(room?["pit_chance"] as? Double == 0.9)
        #expect(room?["gate_chance"] as? Double == 0.5)
    }

    @Test func catalogLoadsPlayableLevelsFromBundle() throws {
        let levels = LevelCatalog.loadFromBundle()
        #expect(levels.map(\.resourceName) == ["level_1", "level_2", "level_3"])
        #expect(levels.map(\.displayName) == ["Level 1", "Level 2", "Level 3"])

        let level1 = try LevelConfig.loadFromBundle(
            named: "level_1",
            subdirectory: LevelCatalog.subdirectory
        )
        #expect(level1.name == "Level 1")
        #expect(level1.width == 100)
        #expect(level1.roomCount == 100)
    }
}
