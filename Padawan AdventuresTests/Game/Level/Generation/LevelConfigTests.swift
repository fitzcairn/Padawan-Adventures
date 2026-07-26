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
          fx: { opened: sfx_gate_opened }
        destructible_wall:
          fx: { destroyed: sfx_wall_destroyed }
        enemies:
          type: spider
          spawn_chance_per_room: 0.8
        pickups:
          health:
            spawn_chance_per_room: 0.8
          energy:
            spawn_chance_per_room: 0.8
        """

    /// Base YAML without puzzle blocks so inheritance tests can append a single `gate:` / `destructible_wall:`.
    private static let baseLevelYAMLWithoutPuzzles = """
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
        enemies:
          type: spider
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
          type: spider
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
        #expect(level.enemies?.type == "spider")
        #expect(level.enemies?.spawnChancePerRoom == 0.8)
        #expect(level.pickups?.health?.spawnChancePerRoom == 0.8)
        #expect(level.pickups?.energy?.spawnChancePerRoom == 0.8)
        #expect(level.music == nil)
        #expect(level.musicCue == .unchanged)
        #expect(level.gameMusic == .fallback)
        #expect(level.artifact == LevelConfig.fallbackArtifact)
    }

    @Test func missingArtifactUsesFallback() throws {
        let level = try LevelConfig.decode(
            from: """
            inherits: base_level
            name: Level 1
            """,
            parents: ["base_level": Self.baseLevelYAML]
        )
        #expect(level.artifact == LevelConfig.fallbackArtifact)
    }

    @Test func childCanOverrideArtifact() throws {
        let level = try LevelConfig.decode(
            from: """
            inherits: base_level
            name: Level 1
            artifact: key.fill
            """,
            parents: ["base_level": Self.baseLevelYAML]
        )
        #expect(level.artifact == "key.fill")
    }

    @Test func decodesTreasureItemID() throws {
        let level = try LevelConfig.decode(
            from: """
            inherits: base_level
            name: Level 1
            treasure: emitter
            """,
            parents: ["base_level": Self.baseLevelYAML]
        )
        #expect(level.treasure == "emitter")
    }

    @Test func omittedTreasureDecodesToNil() throws {
        let level = try LevelConfig.decode(
            from: """
            inherits: base_level
            name: Level 1
            """,
            parents: ["base_level": Self.baseLevelYAML]
        )
        #expect(level.treasure == nil)
    }

    @Test func catalogLevelsCarryTreasureAndArtifact() {
        let levels = LevelCatalog.loadFromBundle()
        #expect(!levels.isEmpty)
        for level in levels {
            #expect(level.treasure != nil, "\(level.resourceName) missing treasure")
            #expect(!level.artifact.isEmpty, "\(level.resourceName) missing artifact")
        }
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

    @Test func decodesBackgroundAndGameBackground() throws {
        let child = """
        inherits: base_level
        name: Level 1
        background: level_engine_bg
        game_background:
          combat: combat_bg
          pit: pit_bg
          destructible_wall: wall_bg
          gate: gate_bg
        """
        let level = try LevelConfig.decode(
            from: child,
            parents: ["base_level": Self.baseLevelYAML]
        )
        #expect(level.background == "level_engine_bg")
        #expect(level.gameBackground.combat == "combat_bg")
        #expect(level.gameBackground.pit == "pit_bg")
        #expect(level.gameBackground.destructibleWall == "wall_bg")
        #expect(level.gameBackground.gate == "gate_bg")
        #expect(level.engineBackgroundNames == [
            "level_engine_bg",
            "combat_bg",
            "pit_bg",
            "wall_bg",
            "gate_bg",
        ])
    }

    @Test func omittedBackgroundFieldsDefaultToNil() throws {
        let level = try LevelConfig.decode(
            from: """
            inherits: base_level
            name: Level 1
            """,
            parents: ["base_level": Self.baseLevelYAML]
        )
        #expect(level.background == nil)
        #expect(level.gameBackground == .fallback)
        #expect(level.engineBackgroundNames.isEmpty)
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
          fx: { opened: sfx_gate_opened_alt }
        destructible_wall:
          fx: { destroyed: sfx_wall_destroyed_alt }
        """
        let level = try LevelConfig.decode(from: yaml)
        #expect(level.gate.fx.trackID(for: "opened") == "sfx_gate_opened_alt")
        #expect(level.destructibleWall.fx.trackID(for: "destroyed") == "sfx_wall_destroyed_alt")
        #expect(level.worldFx.trackID(for: "wall_destroyed") == "sfx_wall_destroyed_alt")
        #expect(level.worldFx.trackID(for: "gate_opened") == "sfx_gate_opened_alt")
    }

    @Test func childCanOverrideInheritedPuzzleFxKeys() throws {
        let child = """
        inherits: base_level
        name: Level 1
        destructible_wall:
          fx: { destroyed: sfx_wall_destroyed_alt }
        """
        let level = try LevelConfig.decode(
            from: child,
            parents: ["base_level": Self.baseLevelYAML]
        )
        #expect(level.destructibleWall.fx.trackID(for: "destroyed") == "sfx_wall_destroyed_alt")
        #expect(level.gate.fx.trackID(for: "opened") == "sfx_gate_opened")
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
        #expect(level.enemies?.type == "spider")
        #expect(level.enemies?.spawnChancePerRoom == 0.8)
        #expect(level.pickups?.health?.spawnChancePerRoom == 0.8)
    }

    @Test func inheritanceRequiresParent() throws {
        let child = """
        inherits: missing_base
        name: Level 1
        """
        #expect(throws: ConfigError.unknownParent(file: "level", parent: "missing_base")) {
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

    @Test func appYAMLOmitsGenerationAndMapSize() throws {
        let yaml = """
        version: 1
        seed: time
        world:
          stories: 1
        """
        let config = try WorldLoader.decodeConfig(from: yaml)
        #expect(config.seed == nil)
        #expect(config.world.stories == 1)
        try config.validate()

        let generation = WorldGenerationConfig.compose(app: config, level: .fallback)
        #expect(generation.world.width == LevelConfig.fallback.width)
        #expect(generation.world.height == LevelConfig.fallback.height)
        #expect(generation.generation == LevelConfig.fallback.generation)
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
        let merged = ConfigStore.deepMerge(base, overwriting: child)
        #expect(merged["name"] as? String == "Level 3")
        #expect(merged["room_count"] as? Int == 100)
        let room = merged["room"] as? [String: Any]
        #expect(room?["pit_chance"] as? Double == 0.9)
        #expect(room?["gate_chance"] as? Double == 0.5)
    }

    @Test func catalogLoadsPlayableLevelsFromBundle() throws {
        let levels = LevelCatalog.loadFromBundle()
        #expect(levels.map(\.resourceName) == [
            "1-tython", "2-tatooine", "3-ilum", "4-kashyyyk",
            "5-dagobah", "6-coruscant", "7-mustafar", "8-geonosis",
        ])
        #expect(levels.map(\.displayName) == [
            "Tython", "Tatooine", "Ilum", "Kashyyyk",
            "Dagobah", "Coruscant", "Mustafar", "Geonosis",
        ])
        #expect(levels.map(\.order) == [1, 2, 3, 4, 5, 6, 7, 8])
        #expect(levels.allSatisfy { !$0.color.isEmpty })
        #expect(levels.allSatisfy { $0.sprite != nil })
        #expect(levels.map { $0.sprite?.root } == Array(repeating: "Sprites/UI/Levels", count: 8))

        let tython = try LevelConfig.loadFromBundle(
            named: "1-tython",
            subdirectory: LevelCatalog.subdirectory
        )
        #expect(tython.name == "Tython")
        #expect(tython.order == 1)
        #expect(tython.color == "#2E7D32")
        #expect(tython.sprite?.root == "Sprites/UI/Levels")
        #expect(tython.sprite?.chromaKey == "#000000")
        #expect(tython.sprite?.chromaKeyTolerance == 2)
        #expect(tython.enemies?.types == ["dino", "treant"])
        #expect(tython.width == 20)
        #expect(tython.roomCount == 5)
    }

    @Test func decodesEnemyTypesListAndLegacyType() throws {
        let withTypes = try LevelConfig.decode(
            from: """
            inherits: base_level
            name: Tatooine
            enemies:
              types: [dino, treant]
              spawn_chance_per_room: 0.5
            """,
            parents: ["base_level": Self.baseLevelYAML]
        )
        #expect(withTypes.enemies?.types == ["dino", "treant"])
        #expect(withTypes.enemies?.type == "dino")
        #expect(withTypes.enemies?.spawnChancePerRoom == 0.5)

        let withLegacy = try LevelConfig.decode(
            from: """
            inherits: base_level
            name: Tython
            enemies:
              type: ice_monster
              spawn_chance_per_room: 0.25
            """,
            parents: ["base_level": Self.baseLevelYAML]
        )
        #expect(withLegacy.enemies?.types == ["ice_monster"])
        #expect(withLegacy.enemies?.type == "ice_monster")
    }

    @Test func decodesOrderAndColor() throws {
        let level = try LevelConfig.decode(
            from: """
            inherits: base_level
            name: Ilum
            order: 3
            color: "#81D4FA"
            """,
            parents: ["base_level": Self.baseLevelYAML]
        )
        #expect(level.order == 3)
        #expect(level.color == "#81D4FA")
    }

    @Test func decodesLevelSprite() throws {
        let level = try LevelConfig.decode(
            from: """
            inherits: base_level
            name: Ilum
            order: 3
            color: "#81D4FA"
            sprite:
              root: Sprites/UI/Levels
              chroma: black_soft
              animations:
                idle:
                  sheet: 3-ilum
                  atlas: 3-ilum-atlas
            """,
            parents: ["base_level": Self.baseLevelYAML]
        )
        #expect(level.sprite?.root == "Sprites/UI/Levels")
        #expect(level.sprite?.chromaKey == "#000000")
        #expect(level.sprite?.chromaKeyTolerance == 2)
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
          words: [CAT, Dog]
        """
        let level = try LevelConfig.decode(from: yaml)
        #expect(level.gate.timerSeconds == 15)
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
        let base = Self.baseLevelYAMLWithoutPuzzles + """

        gate:
          timer_seconds: 22
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
        let base = Self.baseLevelYAMLWithoutPuzzles + """

        gate:
          timer_seconds: 22
          words: [moon]
        """
        let child = """
        inherits: base_level
        name: Level 1
        gate:
          words: [nova, beam]
        """
        let level = try LevelConfig.decode(
            from: child,
            parents: ["base_level": base],
            wordCatalog: catalog
        )
        #expect(level.gate.timerSeconds == 22)
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
        let tython = try LevelConfig.loadFromBundle(
            named: "1-tython",
            subdirectory: LevelCatalog.subdirectory
        )
        #expect(tython.gate.timerSeconds == 30)
        #expect(tython.gate.fx.trackID(for: "win") == nil)
        #expect(tython.gate.fx.trackID(for: "opened") == "sfx_gate_opened")
        #expect(tython.gate.numPaddingLetters == 6)
        #expect(tython.gate.words.map(\.word).contains("gate"))
        #expect(tython.gate.words.contains {
            $0.word == "cat"
                && $0.spelling == "sfx_word_cat"
                && $0.progressiveTrack(forPrefix: "ca") == "sfx_word_cat_ca"
        })
    }

    @Test func bundleBaseLevelProvidesPitDefaults() throws {
        let tython = try LevelConfig.loadFromBundle(
            named: "1-tython",
            subdirectory: LevelCatalog.subdirectory
        )
        #expect(tython.pit.timerSeconds == 30)
        #expect(tython.pit.fx.trackID(for: "win") == "sfx_pit_yay")
        #expect(tython.pit.fx.trackID(for: "lose") == "sfx_pit_fall")
        #expect(tython.pit.numPaddingLetters == 6)
        #expect(tython.pit.words.map(\.word) == ["cat", "dog", "star"])
        #expect(tython.pit.words.contains {
            $0.word == "star"
                && $0.spelling == "sfx_word_star"
                && $0.progressiveTrack(forPrefix: "sta") == "sfx_word_star_sta"
        })
    }

    @Test func decodesOptionalMinigameSoundOverrides() throws {
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
        pit:
          fx: { win: sfx_pit_win_alt, lose: sfx_pit_lose_alt }
          words: [cat]
        gate:
          fx: { win: sfx_gate_win_alt, opened: sfx_gate_opened }
          words: [dog]
        destructible_wall:
          fx: { correct: sfx_wall_correct_alt, destroyed: sfx_wall_destroyed }
          letters: [a]
        """
        let level = try LevelConfig.decode(from: yaml)
        #expect(level.pit.fx.trackID(for: "win") == "sfx_pit_win_alt")
        #expect(level.pit.fx.trackID(for: "lose") == "sfx_pit_lose_alt")
        #expect(level.gate.fx.trackID(for: "win") == "sfx_gate_win_alt")
        #expect(level.destructibleWall.fx.trackID(for: "correct") == "sfx_wall_correct_alt")
    }

    @Test func decodesPitWordIDsFromCatalog() throws {
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
        pit:
          timer_seconds: 25
          words: [star, open]
        """
        let level = try LevelConfig.decode(from: yaml)
        #expect(level.pit.timerSeconds == 25)
        #expect(level.pit.words.map(\.word) == ["open", "star"])
    }

    @Test func rejectsInvalidPitTimer() {
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
        pit:
          timer_seconds: 0
          words: [cat]
        """
        #expect(throws: WorldSeedError.invalidPitTimer(0)) {
            try LevelConfig.decode(from: yaml)
        }
    }

    @Test func rejectsEmptyPitWords() {
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
        pit:
          words: []
        """
        #expect(throws: WorldSeedError.invalidPitWords) {
            try LevelConfig.decode(from: yaml)
        }
    }

    @Test func rejectsUnknownPitWordID() {
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
        pit:
          words: [not_a_real_word]
        """
        #expect(throws: WorldSeedError.invalidPitWords) {
            try LevelConfig.decode(from: yaml)
        }
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
        letter_sound_repeat_seconds: 8
        destructible_wall:
          timer_seconds: 15
          incorrect_replay_delay_seconds: 2
          letter_count_min: 2
          letter_count_max: 3
          letters: [B, a]
        """
        let level = try LevelConfig.decode(from: yaml)
        #expect(level.destructibleWall.timerSeconds == 15)
        #expect(level.letterSoundRepeatSeconds == 8)
        #expect(level.destructibleWall.incorrectReplayDelaySeconds == 2)
        #expect(level.destructibleWall.letterCountMin == 2)
        #expect(level.destructibleWall.letterCountMax == 3)
        #expect(level.destructibleWall.letterIDs == ["b", "a"])
        #expect(level.destructibleWall.letters.map(\.letter) == ["a", "b"])
        #expect(level.destructibleWall.letters.map(\.pronunciation) == [
            "sfx_letter_a_pronunciation",
            "sfx_letter_b_pronunciation",
        ])
    }

    @Test func inheritsDestructibleWallConfigFromBase() throws {
        let base = Self.baseLevelYAMLWithoutPuzzles + """

        letter_sound_repeat_seconds: 6
        destructible_wall:
          timer_seconds: 22
          letter_count_min: 1
          letter_count_max: 2
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
        #expect(level.letterSoundRepeatSeconds == 6)
        #expect(level.destructibleWall.letterCountMin == 1)
        #expect(level.destructibleWall.letterCountMax == 2)
        #expect(level.destructibleWall.letters.map(\.letter) == ["a", "c"])
    }

    @Test func childCanOverrideInheritedDestructibleWallLetterIDs() throws {
        let base = Self.baseLevelYAMLWithoutPuzzles + """

        letter_sound_repeat_seconds: 6
        destructible_wall:
          timer_seconds: 22
          letters: [a]
        """
        let child = """
        inherits: base_level
        name: Level 1
        letter_sound_repeat_seconds: 12
        destructible_wall:
          letters: [b]
        """
        let level = try LevelConfig.decode(
            from: child,
            parents: ["base_level": base]
        )
        #expect(level.destructibleWall.timerSeconds == 22)
        #expect(level.letterSoundRepeatSeconds == 12)
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

    @Test func rejectsInvalidDestructibleWallLetterCountRange() {
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
          letter_count_min: 4
          letter_count_max: 2
          letters: [a]
        """
        #expect(throws: WorldSeedError.invalidDestructibleWallLetterCountRange(min: 4, max: 2)) {
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
        let tython = try LevelConfig.loadFromBundle(
            named: "1-tython",
            subdirectory: LevelCatalog.subdirectory
        )
        #expect(tython.destructibleWall.timerSeconds == 30)
        #expect(tython.letterSoundRepeatSeconds == 3)
        #expect(tython.destructibleWall.incorrectReplayDelaySeconds == 1)
        #expect(tython.destructibleWall.letterCountMin == 4)
        #expect(tython.destructibleWall.letterCountMax == 8)
        #expect(tython.destructibleWall.fx.trackID(for: "correct") == nil)
        #expect(tython.destructibleWall.fx.trackID(for: "destroyed") == "sfx_wall_destroyed")
        #expect(tython.destructibleWall.letters.map(\.letter) == ["a", "b", "c", "d", "e", "f", "g", "h"])
        #expect(tython.artifact == "leaf.fill")
    }

    @Test func decodesTopLevelLetterSoundRepeatSeconds() throws {
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
          letters: [a]
        """
        let level = try LevelConfig.decode(from: yaml)
        #expect(level.letterSoundRepeatSeconds == 3)
    }

    @Test func decodesEnemiesSpawnBlock() throws {
        let yaml = """
        name: Level
        width: 10
        height: 10
        algorithm: rooms_doors
        room_count: 2
        corridor_width: 2
        room:
          min_room_size: 4
          max_room_size: 12
          pit_chance: 0.0
          wall_destructible_chance: 0.0
          gate_chance: 0.0
        enemies:
          types: [spider, ice_monster]
          spawn_chance_per_room: 0.8
        """

        let level = try LevelConfig.decode(from: yaml)
        #expect(level.enemies?.types == ["spider", "ice_monster"])
        #expect(level.enemies?.type == "spider")
        #expect(level.enemies?.spawnChancePerRoom == 0.8)
        try level.validate()
    }

    @Test func rejectsInvalidEnemySpawnChance() throws {
        let yaml = """
        name: Level
        width: 10
        height: 10
        algorithm: rooms_doors
        room_count: 2
        corridor_width: 2
        room:
          min_room_size: 4
          max_room_size: 12
          pit_chance: 0.0
          wall_destructible_chance: 0.0
          gate_chance: 0.0
        enemies:
          type: spider
          spawn_chance_per_room: 1.5
        """

        #expect(throws: WorldSeedError.invalidEnemySpawnChance(1.5)) {
            try LevelConfig.decode(from: yaml)
        }
    }

    @Test func decodesPickupsSpawnBlock() throws {
        let yaml = """
        name: Level
        width: 10
        height: 10
        algorithm: rooms_doors
        room_count: 2
        corridor_width: 2
        room:
          min_room_size: 4
          max_room_size: 12
          pit_chance: 0.0
          wall_destructible_chance: 0.0
          gate_chance: 0.0
        pickups:
          health:
            spawn_chance_per_room: 0.8
          energy:
            spawn_chance_per_room: 0.5
        """

        let level = try LevelConfig.decode(from: yaml)
        #expect(level.pickups?.health?.spawnChancePerRoom == 0.8)
        #expect(level.pickups?.energy?.spawnChancePerRoom == 0.5)
        try level.validate()
    }

    @Test func rejectsInvalidPickupSpawnChance() throws {
        let yaml = """
        name: Level
        width: 10
        height: 10
        algorithm: rooms_doors
        room_count: 2
        corridor_width: 2
        room:
          min_room_size: 4
          max_room_size: 12
          pit_chance: 0.0
          wall_destructible_chance: 0.0
          gate_chance: 0.0
        pickups:
          health:
            spawn_chance_per_room: -0.1
        """

        #expect(throws: WorldSeedError.invalidPickupSpawnChance(kind: .health, chance: -0.1)) {
            try LevelConfig.decode(from: yaml)
        }
    }

    @Test func rejectsInvalidPitSize() throws {
        let yaml = """
        name: Level
        width: 10
        height: 10
        algorithm: rooms_doors
        room_count: 2
        corridor_width: 2
        room:
          min_room_size: 4
          max_room_size: 12
          pit_chance: 0.2
          pit_mean_size: 6
          pit_max_size: 5
          wall_destructible_chance: 0.0
          gate_chance: 0.0
        """

        #expect(throws: WorldSeedError.invalidRoomPitSize(mean: 6, max: 5)) {
            try LevelConfig.decode(from: yaml)
        }
    }

    @Test func rejectsInvalidGateChance() throws {
        let yaml = """
        name: Level
        width: 10
        height: 10
        algorithm: rooms_doors
        room_count: 2
        corridor_width: 2
        room:
          min_room_size: 4
          max_room_size: 12
          pit_chance: 0.0
          wall_destructible_chance: 0.0
          gate_chance: 1.5
        """

        #expect(throws: WorldSeedError.invalidRoomGateChance(1.5)) {
            try LevelConfig.decode(from: yaml)
        }
    }

    @Test func rejectsCorridorNarrowerThanTwo() throws {
        let yaml = """
        name: Level
        width: 10
        height: 10
        algorithm: rooms_doors
        room_count: 2
        corridor_width: 1
        room:
          min_room_size: 4
          max_room_size: 12
          pit_chance: 0.0
          wall_destructible_chance: 0.0
          gate_chance: 0.0
        """

        #expect(throws: WorldSeedError.corridorTooNarrow(1)) {
            try LevelConfig.decode(from: yaml)
        }
    }
}
