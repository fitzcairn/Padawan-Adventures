import Testing
@testable import Padawan_Adventures

struct LevelConfigTests {
    private static let baseLevelYAML = """
        name: Level
        music: level_theme
        game_music:
          combat: combat_theme
          pit: pit_theme
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
        gate:
          fx: { opened: sfx_gate_opened }
          minigames:
            - type: spelling
              timer_seconds: 30
              words: [cat, dog, star]
              music: gate_theme
            - type: letter_match
              timer_seconds: 30
              letters: [a, b, c, d, e, f, g, h]
              music: destructible_wall_theme
        enemies:
          type: spider
          spawn_chance_per_room: 0.8
        pickups:
          health:
            spawn_chance_per_room: 0.8
          energy:
            spawn_chance_per_room: 0.8
        """

    /// Base YAML without the `gate:` block so inheritance tests can append their own.
    private static let baseLevelYAMLWithoutPuzzles = """
        name: Level
        music: level_theme
        game_music:
          combat: combat_theme
          pit: pit_theme
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
          partition_gate_chance: 0.8
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
        #expect(level.room.partitionGateChance == 0.8)
        #expect(level.enemies?.type == "spider")
        #expect(level.enemies?.spawnChancePerRoom == 0.8)
        #expect(level.pickups?.health?.spawnChancePerRoom == 0.8)
        #expect(level.pickups?.energy?.spawnChancePerRoom == 0.8)
        #expect(level.music == nil)
        #expect(level.musicCue == .unchanged)
        #expect(level.gameMusic == .fallback)
        #expect(level.artifact == LevelConfig.fallbackArtifact)
        #expect(level.letters.set == LevelConfig.fallbackLetters.set)
    }

    @Test func decodesLetterSpriteSet() throws {
        let level = try LevelConfig.decode(from: """
        name: Tatooine
        width: 20
        height: 20
        algorithm: rooms_doors
        room_count: 5
        corridor_width: 2
        room:
          min_room_size: 4
          max_room_size: 12
          pit_chance: 0.2
          pit_mean_size: 2
          pit_max_size: 5
          partition_gate_chance: 0.8
        letters:
          set: 2-tatooine
        """)
        #expect(level.letters.set == "2-tatooine")
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
          partition_gate_chance: 0
        gate:
          fx: { opened: sfx_gate_opened_alt }
          minigames:
            - type: spelling
              words: [cat]
        """
        let level = try LevelConfig.decode(from: yaml)
        #expect(level.gate.fx.trackID(for: "opened") == "sfx_gate_opened_alt")
        #expect(level.worldFx.trackID(for: "gate_opened") == "sfx_gate_opened_alt")
    }

    @Test func childCanOverrideInheritedGateFxKeys() throws {
        let child = """
        inherits: base_level
        name: Level 1
        gate:
          fx: { opened: sfx_gate_opened_alt }
        """
        let level = try LevelConfig.decode(
            from: child,
            parents: ["base_level": Self.baseLevelYAML]
        )
        #expect(level.gate.fx.trackID(for: "opened") == "sfx_gate_opened_alt")
        #expect(level.worldFx.trackID(for: "gate_opened") == "sfx_gate_opened_alt")
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
        #expect(level.room.partitionGateChance == 0.8)
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
                "partition_gate_chance": 0.5,
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
        #expect(room?["partition_gate_chance"] as? Double == 0.5)
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

    @Test func decodesGateConfigWithDefaultsWhenOmitted() throws {
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
          partition_gate_chance: 0
        """)
        #expect(level.gate == GateConfig.fallback)
    }

    @Test func decodesGateSpellingMinigameFromYAML() throws {
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
          partition_gate_chance: 0
        gate:
          fx: { opened: sfx_gate_opened }
          minigames:
            - type: spelling
              timer_seconds: 15
              words: [CAT, Dog]
        """
        let level = try LevelConfig.decode(from: yaml)
        guard case .spelling(let spelling) = level.gate.minigames.first else {
            Issue.record("expected spelling minigame")
            return
        }
        #expect(spelling.timerSeconds == 15)
        #expect(spelling.wordIDs == ["cat", "dog"])
        #expect(spelling.words.map(\.word) == ["cat", "dog"])
        #expect(spelling.words.map(\.spelling) == ["sfx_word_cat", "sfx_word_dog"])
        #expect(spelling.words[0].progressiveTrack(forPrefix: "ca") == "sfx_word_cat_ca")
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
          fx: { opened: sfx_gate_opened }
          minigames:
            - type: spelling
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
        guard case .spelling(let spelling) = level.gate.minigames.first else {
            Issue.record("expected spelling minigame")
            return
        }
        #expect(spelling.timerSeconds == 22)
        #expect(spelling.words.map(\.word) == ["moon", "sun"])
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
          fx: { opened: sfx_gate_opened }
          minigames:
            - type: spelling
              timer_seconds: 22
              words: [moon]
        """
        let child = """
        inherits: base_level
        name: Level 1
        gate:
          minigames:
            - type: spelling
              timer_seconds: 22
              words: [nova, beam]
        """
        let level = try LevelConfig.decode(
            from: child,
            parents: ["base_level": base],
            wordCatalog: catalog
        )
        guard case .spelling(let spelling) = level.gate.minigames.first else {
            Issue.record("expected spelling minigame")
            return
        }
        // `minigames` lists replace on inherit (not deep-merged per entry).
        #expect(spelling.timerSeconds == 22)
        #expect(spelling.words.map(\.word) == ["beam", "nova"])
        #expect(spelling.words.map(\.spelling) == [
            "sfx_word_beam",
            "sfx_word_nova",
        ])
    }

    @Test func rejectsInvalidGateSpellingTimer() {
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
          partition_gate_chance: 0
        gate:
          fx: { opened: sfx_gate_opened }
          minigames:
            - type: spelling
              timer_seconds: 0
              words: [cat]
        """
        #expect(throws: WorldSeedError.invalidGateTimer(0)) {
            try LevelConfig.decode(from: yaml)
        }
    }

    @Test func rejectsEmptyGateSpellingWords() {
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
          partition_gate_chance: 0
        gate:
          fx: { opened: sfx_gate_opened }
          minigames:
            - type: spelling
              words: []
        """
        #expect(throws: WorldSeedError.invalidGateWords) {
            try LevelConfig.decode(from: yaml)
        }
    }

    @Test func rejectsUnknownGateSpellingWordID() {
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
          partition_gate_chance: 0
        gate:
          fx: { opened: sfx_gate_opened }
          minigames:
            - type: spelling
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
        #expect(tython.gate.fx.trackID(for: "opened") == "sfx_gate_opened")
        #expect(!tython.gate.minigames.isEmpty)
        let spellingConfigs = tython.gate.minigames.compactMap { minigame -> GateSpellingConfig? in
            if case .spelling(let c) = minigame { return c }
            return nil
        }
        #expect(!spellingConfigs.isEmpty)
        let spelling = spellingConfigs[0]
        #expect(spelling.timerSeconds == 30)
        #expect(spelling.numPaddingLetters == 6)
        #expect(spelling.words.map(\.word).contains("gate"))
        #expect(spelling.words.contains {
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
          partition_gate_chance: 0
        pit:
          fx: { win: sfx_pit_win_alt, lose: sfx_pit_lose_alt }
          words: [cat]
        gate:
          fx: { opened: sfx_gate_opened }
          minigames:
            - type: spelling
              fx: { win: sfx_gate_win_alt }
              words: [dog]
            - type: letter_match
              fx: { correct: sfx_wall_correct_alt }
              letters: [a]
        """
        let level = try LevelConfig.decode(from: yaml)
        #expect(level.pit.fx.trackID(for: "win") == "sfx_pit_win_alt")
        #expect(level.pit.fx.trackID(for: "lose") == "sfx_pit_lose_alt")
        #expect(level.gate.fx.trackID(for: "opened") == "sfx_gate_opened")
        if case .spelling(let spelling) = level.gate.minigames.first {
            #expect(spelling.fx.trackID(for: "win") == "sfx_gate_win_alt")
        }
        if case .letterMatch(let letterMatch) = level.gate.minigames.last {
            #expect(letterMatch.fx.trackID(for: "correct") == "sfx_wall_correct_alt")
        }
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
        pit:
          words: [not_a_real_word]
        """
        #expect(throws: WorldSeedError.invalidPitWords) {
            try LevelConfig.decode(from: yaml)
        }
    }

    @Test func decodesGateLetterMatchConfigWithDefaultsWhenOmitted() throws {
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
          partition_gate_chance: 0
        """)
        #expect(level.gate == GateConfig.fallback)
    }

    @Test func decodesGateLetterMatchConfigFromYAML() throws {
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
          partition_gate_chance: 0
        letter_sound_repeat_seconds: 8
        gate:
          fx: { opened: sfx_gate_opened }
          minigames:
            - type: letter_match
              timer_seconds: 15
              incorrect_replay_delay_seconds: 2
              letter_count_min: 2
              letter_count_max: 3
              letters: [B, a]
        """
        let level = try LevelConfig.decode(from: yaml)
        #expect(level.letterSoundRepeatSeconds == 8)
        guard case .letterMatch(let lm) = level.gate.minigames.first else {
            Issue.record("expected letter_match minigame")
            return
        }
        #expect(lm.timerSeconds == 15)
        #expect(lm.incorrectReplayDelaySeconds == 2)
        #expect(lm.letterCountMin == 2)
        #expect(lm.letterCountMax == 3)
        #expect(lm.letterIDs == ["b", "a"])
        #expect(lm.letters.map(\.letter) == ["a", "b"])
        #expect(lm.letters.map(\.pronunciation) == [
            "sfx_letter_a_pronunciation",
            "sfx_letter_b_pronunciation",
        ])
    }

    @Test func inheritsGateLetterMatchConfigFromBase() throws {
        let base = Self.baseLevelYAMLWithoutPuzzles + """

        letter_sound_repeat_seconds: 6
        gate:
          fx: { opened: sfx_gate_opened }
          minigames:
            - type: letter_match
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
        #expect(level.letterSoundRepeatSeconds == 6)
        guard case .letterMatch(let lm) = level.gate.minigames.first else {
            Issue.record("expected letter_match minigame")
            return
        }
        #expect(lm.timerSeconds == 22)
        #expect(lm.letterCountMin == 1)
        #expect(lm.letterCountMax == 2)
        #expect(lm.letters.map(\.letter) == ["a", "c"])
    }

    @Test func childCanOverrideInheritedGateLetterMatchLetterIDs() throws {
        let base = Self.baseLevelYAMLWithoutPuzzles + """

        letter_sound_repeat_seconds: 6
        gate:
          fx: { opened: sfx_gate_opened }
          minigames:
            - type: letter_match
              timer_seconds: 22
              letters: [a]
        """
        let child = """
        inherits: base_level
        name: Level 1
        letter_sound_repeat_seconds: 12
        gate:
          minigames:
            - type: letter_match
              letters: [b]
        """
        let level = try LevelConfig.decode(
            from: child,
            parents: ["base_level": base]
        )
        #expect(level.letterSoundRepeatSeconds == 12)
        guard case .letterMatch(let lm) = level.gate.minigames.first else {
            Issue.record("expected letter_match minigame")
            return
        }
        #expect(lm.letters.map(\.letter) == ["b"])
    }

    @Test func rejectsInvalidGateLetterMatchTimer() {
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
          partition_gate_chance: 0
        gate:
          fx: { opened: sfx_gate_opened }
          minigames:
            - type: letter_match
              timer_seconds: 0
              letters: [a]
        """
        #expect(throws: WorldSeedError.invalidGateLetterMatchTimer(0)) {
            try LevelConfig.decode(from: yaml)
        }
    }

    @Test func rejectsInvalidGateLetterMatchLetterCountRange() {
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
          partition_gate_chance: 0
        gate:
          fx: { opened: sfx_gate_opened }
          minigames:
            - type: letter_match
              letter_count_min: 4
              letter_count_max: 2
              letters: [a]
        """
        #expect(throws: WorldSeedError.invalidGateLetterMatchLetterCountRange(min: 4, max: 2)) {
            try LevelConfig.decode(from: yaml)
        }
    }

    @Test func rejectsEmptyGateLetterMatchLetters() {
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
          partition_gate_chance: 0
        gate:
          fx: { opened: sfx_gate_opened }
          minigames:
            - type: letter_match
              letters: []
        """
        #expect(throws: WorldSeedError.invalidGateLetterMatchLetters) {
            try LevelConfig.decode(from: yaml)
        }
    }

    @Test func rejectsUnknownGateLetterMatchLetterID() {
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
          partition_gate_chance: 0
        gate:
          fx: { opened: sfx_gate_opened }
          minigames:
            - type: letter_match
              letters: [z]
        """
        #expect(throws: WorldSeedError.invalidGateLetterMatchLetters) {
            try LevelConfig.decode(from: yaml)
        }
    }

    @Test func bundleBaseLevelProvidesGateLetterMatchDefaults() throws {
        let tython = try LevelConfig.loadFromBundle(
            named: "1-tython",
            subdirectory: LevelCatalog.subdirectory
        )
        let letterMatchConfigs = tython.gate.minigames.compactMap { minigame -> GateLetterMatchConfig? in
            if case .letterMatch(let c) = minigame { return c }
            return nil
        }
        #expect(!letterMatchConfigs.isEmpty)
        let lm = letterMatchConfigs[0]
        #expect(lm.timerSeconds == 30)
        #expect(lm.incorrectReplayDelaySeconds == 1)
        #expect(lm.letterCountMin == 4)
        #expect(lm.letterCountMax == 8)
        #expect(lm.letters.map(\.letter) == ["a", "b", "c", "d", "e", "f", "g", "h"])
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
          partition_gate_chance: 0
        gate:
          fx: { opened: sfx_gate_opened }
          minigames:
            - type: letter_match
              letters: [a]
        """
        let level = try LevelConfig.decode(from: yaml)
        #expect(level.letterSoundRepeatSeconds == 3)
    }

    @Test func gateConfigLooksUpMinigameByKind() {
        let config = GateConfig.fallback
        #expect(config.distinctMinigameKinds == [.spelling, .letterMatch])
        guard case .letterMatch = config.minigame(for: .letterMatch) else {
            Issue.record("expected letter_match config")
            return
        }
        guard case .spelling = config.minigame(for: .spelling) else {
            Issue.record("expected spelling config")
            return
        }
        let duplicated = GateConfig(
            fx: config.fx,
            minigames: [
                .spelling(.fallback),
                .letterMatch(.fallback),
                .spelling(.fallback),
            ]
        )
        #expect(duplicated.distinctMinigameKinds == [.spelling, .letterMatch])
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
        """

        #expect(throws: WorldSeedError.invalidRoomPitSize(mean: 6, max: 5)) {
            try LevelConfig.decode(from: yaml)
        }
    }

    @Test func rejectsInvalidPartitionGateChance() throws {
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
          partition_gate_chance: 1.5
        """

        #expect(throws: WorldSeedError.invalidRoomPartitionGateChance(1.5)) {
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
        """

        #expect(throws: WorldSeedError.corridorTooNarrow(1)) {
            try LevelConfig.decode(from: yaml)
        }
    }
}
