import Testing
@testable import Padawan_Adventures

struct LevelConfigTests {
    private static let baseLevelYAML = """
        name: Level
        music: level_theme
        game_music:
          combat: combat_theme
          pit: pit_theme
          destructible_wall: destructible_wall_theme
          gate: gate_theme
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
        gate:
          gate_opened: sfx_gate_opened
        destructible_wall:
          wall_destroyed: sfx_wall_destroyed
        enemies:
          type: grunt
          spawn_chance_per_room: 0.8
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
        enemies:
          type: grunt
          spawn_chance_per_room: 0.8
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
        #expect(level.enemies?.type == "grunt")
        #expect(level.enemies?.spawnChancePerRoom == 0.8)
        #expect(level.pickups?.health?.spawnChancePerRoom == 0.8)
        #expect(level.pickups?.energy?.spawnChancePerRoom == 0.8)
        #expect(level.music == nil)
        #expect(level.musicCue == .unchanged)
        #expect(level.gameMusic == .fallback)
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
        #expect(level.gameMusic.combatCue == .track("combat_theme"))
        #expect(level.gameMusic.pitCue == .track("pit_theme"))
        #expect(level.gameMusic.destructibleWallCue == .track("destructible_wall_theme"))
        #expect(level.gameMusic.gateCue == .track("gate_theme"))
    }

    @Test func childCanOverrideGameMusicKeys() throws {
        let child = """
        inherits: base_level
        name: Level 1
        game_music:
          combat: combat_theme_alt
          gate: silence
        """
        let level = try LevelConfig.decode(
            from: child,
            parents: ["base_level": Self.baseLevelYAML]
        )
        #expect(level.gameMusic.combat == "combat_theme_alt")
        #expect(level.gameMusic.gateCue == .silence)
        #expect(level.gameMusic.pit == "pit_theme")
        #expect(level.gameMusic.destructibleWall == "destructible_wall_theme")
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

    @Test func decodesPuzzleWorldFx() throws {
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
        gate:
          gate_opened: sfx_gate_opened_alt
        destructible_wall:
          wall_destroyed: sfx_wall_destroyed_alt
        """
        let level = try LevelConfig.decode(from: yaml)
        #expect(level.gate.gateOpened == "sfx_gate_opened_alt")
        #expect(level.destructibleWall.wallDestroyed == "sfx_wall_destroyed_alt")
        #expect(level.worldFx.trackID(for: "wall_destroyed") == "sfx_wall_destroyed_alt")
        #expect(level.worldFx.trackID(for: "gate_opened") == "sfx_gate_opened_alt")
    }

    @Test func childCanOverrideInheritedPuzzleFxKeys() throws {
        let child = """
        inherits: base_level
        name: Level 1
        destructible_wall:
          wall_destroyed: sfx_wall_destroyed_alt
        """
        let level = try LevelConfig.decode(
            from: child,
            parents: ["base_level": Self.baseLevelYAML]
        )
        #expect(level.destructibleWall.wallDestroyed == "sfx_wall_destroyed_alt")
        #expect(level.gate.gateOpened == "sfx_gate_opened")
        #expect(level.worldFx.trackID(for: "wall_destroyed") == "sfx_wall_destroyed_alt")
        #expect(level.worldFx.trackID(for: "gate_opened") == "sfx_gate_opened")
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
        #expect(level.enemies?.type == "grunt")
        #expect(level.enemies?.spawnChancePerRoom == 0.8)
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
        #expect {
            try LevelConfig.decode(from: yaml)
        } throws: { error in
            guard let error = error as? WorldSeedError,
                  case .decodeFailed = error else {
                return false
            }
            return true
        }
    }

    @Test func worldYAMLAllowsMissingGenerationAndMapSize() throws {
        let yaml = """
        version: 1
        seed: time
        world:
          stories: 1
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
        #expect(level1.width == 20)
        #expect(level1.roomCount == 5)
    }

    @Test func decodesGatePuzzleConfigWithDefaultsWhenOmitted() throws {
        let level = try LevelConfig.decode(from: """
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
        """)
        #expect(level.gate == GatePuzzleConfig.fallback)
    }

    @Test func decodesGatePuzzleConfigFromYAML() throws {
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
        gate:
          timer_seconds: 15
          word_sound_repeat_seconds: 8
          words: [CAT, Dog]
        """
        let level = try LevelConfig.decode(from: yaml)
        #expect(level.gate.timerSeconds == 15)
        #expect(level.gate.wordSoundRepeatSeconds == 8)
        #expect(level.gate.wordIDs == ["cat", "dog"])
        #expect(level.gate.words.map(\.word) == ["cat", "dog"])
        #expect(level.gate.words.map(\.spelling) == ["sfx_word_cat", "sfx_word_dog"])
        #expect(level.gate.words[0].progressiveTrack(forPrefix: "ca") == "sfx_word_cat_ca")
    }

    @Test func inheritsGateConfigFromBase() throws {
        let catalog = try WordCatalog.decode(from: """
        words:
          moon:
            spelling: sfx_word_moon
            progressive:
              m: sfx_word_moon_m
              mo: sfx_word_moon_mo
              moo: sfx_word_moon_moo
              moon: sfx_word_moon_moon
          sun:
            spelling: sfx_word_sun
            progressive:
              s: sfx_word_sun_s
              su: sfx_word_sun_su
              sun: sfx_word_sun_sun
        """)
        let base = Self.baseLevelYAML + """

        gate:
          timer_seconds: 22
          word_sound_repeat_seconds: 6
          words: [moon, sun]
        """
        let child = """
        inherits: base_level
        name: Level 1
        """
        let level = try LevelConfig.decode(
            from: child,
            parents: ["base_level": base],
            wordCatalog: catalog
        )
        #expect(level.gate.timerSeconds == 22)
        #expect(level.gate.wordSoundRepeatSeconds == 6)
        #expect(level.gate.words.map(\.word) == ["moon", "sun"])
    }

    @Test func childCanOverrideInheritedGateWordIDs() throws {
        let catalog = try WordCatalog.decode(from: """
        words:
          moon:
            spelling: sfx_word_moon
            progressive:
              m: sfx_word_moon_m
              mo: sfx_word_moon_mo
              moo: sfx_word_moon_moo
              moon: sfx_word_moon_moon
          nova:
            spelling: sfx_word_nova
            progressive:
              n: sfx_word_nova_n
              no: sfx_word_nova_no
              nov: sfx_word_nova_nov
              nova: sfx_word_nova_nova
          beam:
            spelling: sfx_word_beam
            progressive:
              b: sfx_word_beam_b
              be: sfx_word_beam_be
              bea: sfx_word_beam_bea
              beam: sfx_word_beam_beam
        """)
        let base = Self.baseLevelYAML + """

        gate:
          timer_seconds: 22
          word_sound_repeat_seconds: 6
          words: [moon]
        """
        let child = """
        inherits: base_level
        name: Level 1
        gate:
          word_sound_repeat_seconds: 12
          words: [nova, beam]
        """
        let level = try LevelConfig.decode(
            from: child,
            parents: ["base_level": base],
            wordCatalog: catalog
        )
        #expect(level.gate.timerSeconds == 22)
        #expect(level.gate.wordSoundRepeatSeconds == 12)
        // Word id lists replace (not deep-merge) on inherit.
        #expect(level.gate.words.map(\.word) == ["beam", "nova"])
        #expect(level.gate.words.map(\.spelling) == [
            "sfx_word_beam",
            "sfx_word_nova",
        ])
    }

    @Test func rejectsInvalidGateTimer() {
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
        gate:
          timer_seconds: 0
          words: [cat]
        """
        #expect(throws: WorldSeedError.invalidGateTimer(0)) {
            try LevelConfig.decode(from: yaml)
        }
    }

    @Test func rejectsInvalidGateWordSoundRepeat() {
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
        gate:
          word_sound_repeat_seconds: 0
          words: [cat]
        """
        #expect(throws: WorldSeedError.invalidGateWordSoundRepeat(0)) {
            try LevelConfig.decode(from: yaml)
        }
    }

    @Test func rejectsEmptyGateWords() {
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
        gate:
          words: []
        """
        #expect(throws: WorldSeedError.invalidGateWords) {
            try LevelConfig.decode(from: yaml)
        }
    }

    @Test func rejectsUnknownGateWordID() {
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
        gate:
          words: [not_a_real_word]
        """
        #expect(throws: WorldSeedError.invalidGateWords) {
            try LevelConfig.decode(from: yaml)
        }
    }

    @Test func bundleBaseLevelProvidesGateDefaults() throws {
        let level1 = try LevelConfig.loadFromBundle(
            named: "level_1",
            subdirectory: LevelCatalog.subdirectory
        )
        #expect(level1.gate.timerSeconds == 30)
        #expect(level1.gate.wordSoundRepeatSeconds == 10)
        #expect(level1.gate.winSound == "sfx_gate_win")
        #expect(level1.gate.numPaddingLetters == 6)
        #expect(level1.gate.words.map(\.word).contains("gate"))
        #expect(level1.gate.words.contains {
            $0.word == "cat"
                && $0.spelling == "sfx_word_cat"
                && $0.progressiveTrack(forPrefix: "ca") == "sfx_word_cat_ca"
        })
    }

    @Test func decodesDestructibleWallPuzzleConfigWithDefaultsWhenOmitted() throws {
        let level = try LevelConfig.decode(from: """
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
        """)
        #expect(level.destructibleWall == DestructibleWallPuzzleConfig.fallback)
    }

    @Test func decodesDestructibleWallPuzzleConfigFromYAML() throws {
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
        destructible_wall:
          timer_seconds: 15
          letter_sound_repeat_seconds: 8
          incorrect_replay_delay_seconds: 2
          letter_count_mean: 3
          win_sound: sfx_wall_yay
          letters: [B, a]
        """
        let level = try LevelConfig.decode(from: yaml)
        #expect(level.destructibleWall.timerSeconds == 15)
        #expect(level.destructibleWall.letterSoundRepeatSeconds == 8)
        #expect(level.destructibleWall.incorrectReplayDelaySeconds == 2)
        #expect(level.destructibleWall.letterCountMean == 3)
        #expect(level.destructibleWall.letterIDs == ["b", "a"])
        #expect(level.destructibleWall.letters.map(\.letter) == ["a", "b"])
        #expect(level.destructibleWall.letters.map(\.pronunciation) == [
            "sfx_letter_a_pronunciation",
            "sfx_letter_b_pronunciation",
        ])
    }

    @Test func inheritsDestructibleWallConfigFromBase() throws {
        let base = Self.baseLevelYAML + """

        destructible_wall:
          timer_seconds: 22
          letter_sound_repeat_seconds: 6
          letter_count_mean: 2
          letters: [a, c]
        """
        let child = """
        inherits: base_level
        name: Level 1
        """
        let level = try LevelConfig.decode(
            from: child,
            parents: ["base_level": base]
        )
        #expect(level.destructibleWall.timerSeconds == 22)
        #expect(level.destructibleWall.letterSoundRepeatSeconds == 6)
        #expect(level.destructibleWall.letterCountMean == 2)
        #expect(level.destructibleWall.letters.map(\.letter) == ["a", "c"])
    }

    @Test func childCanOverrideInheritedDestructibleWallLetterIDs() throws {
        let base = Self.baseLevelYAML + """

        destructible_wall:
          timer_seconds: 22
          letter_sound_repeat_seconds: 6
          letters: [a]
        """
        let child = """
        inherits: base_level
        name: Level 1
        destructible_wall:
          letter_sound_repeat_seconds: 12
          letters: [b]
        """
        let level = try LevelConfig.decode(
            from: child,
            parents: ["base_level": base]
        )
        #expect(level.destructibleWall.timerSeconds == 22)
        #expect(level.destructibleWall.letterSoundRepeatSeconds == 12)
        // Letter id lists replace (not deep-merge) on inherit.
        #expect(level.destructibleWall.letters.map(\.letter) == ["b"])
    }

    @Test func rejectsInvalidDestructibleWallTimer() {
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
        destructible_wall:
          timer_seconds: 0
          letters: [a]
        """
        #expect(throws: WorldSeedError.invalidDestructibleWallTimer(0)) {
            try LevelConfig.decode(from: yaml)
        }
    }

    @Test func rejectsEmptyDestructibleWallLetters() {
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
        destructible_wall:
          letters: []
        """
        #expect(throws: WorldSeedError.invalidDestructibleWallLetters) {
            try LevelConfig.decode(from: yaml)
        }
    }

    @Test func rejectsUnknownDestructibleWallLetterID() {
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
        destructible_wall:
          letters: [z]
        """
        #expect(throws: WorldSeedError.invalidDestructibleWallLetters) {
            try LevelConfig.decode(from: yaml)
        }
    }

    @Test func bundleBaseLevelProvidesDestructibleWallDefaults() throws {
        let level1 = try LevelConfig.loadFromBundle(
            named: "level_1",
            subdirectory: LevelCatalog.subdirectory
        )
        #expect(level1.destructibleWall.timerSeconds == 30)
        #expect(level1.letterSoundRepeatSeconds == 3)
        #expect(level1.destructibleWall.letterSoundRepeatSeconds == 3)
        #expect(level1.destructibleWall.incorrectReplayDelaySeconds == 1)
        #expect(level1.destructibleWall.letterCountMean == 3)
        #expect(level1.destructibleWall.winSound == "sfx_wall_yay")
        #expect(level1.destructibleWall.letters.map(\.letter) == ["a", "b", "c", "d", "e", "f", "g", "h"])
    }

    @Test func topLevelLetterSoundRepeatOverridesWallNestedValue() throws {
        let yaml = """
        name: Level 1
        width: 20
        height: 20
        algorithm: rooms_doors
        room_count: 4
        corridor_width: 2
        letter_sound_repeat_seconds: 3
        room:
          min_room_size: 4
          max_room_size: 8
          pit_chance: 0
          wall_destructible_chance: 0
          gate_chance: 0
        destructible_wall:
          letter_sound_repeat_seconds: 9
          letters: [a]
        """
        let level = try LevelConfig.decode(from: yaml)
        #expect(level.letterSoundRepeatSeconds == 3)
        #expect(level.destructibleWall.letterSoundRepeatSeconds == 3)
    }
}
