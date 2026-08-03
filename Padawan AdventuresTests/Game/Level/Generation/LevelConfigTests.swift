import Testing
@testable import Padawan_Adventures

struct LevelConfigTests {
    private static let baseLevelYAML = """
        name: Level
        music: level
        game_music:
          combat: combat
          pit: pit
          gate: gate
        width: 100
        height: 100
        algorithm: rooms_doors
        room_count: 100
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
              words: [cat, dog, star]
              music: gate
            - type: letter_match
              letters: [a, b, c, d, e, f, g, h]
              music: gate
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
        music: level
        game_music:
          combat: combat
          pit: pit
          gate: gate
        width: 100
        height: 100
        algorithm: rooms_doors
        room_count: 100
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

    @Test func rejectsUnsupportedGenerationAlgorithm() {
        #expect {
            try LevelConfig.decode(from: """
            name: Level 1
            width: 20
            height: 20
            algorithm: cellular_automata
            room_count: 5
            room:
              min_room_size: 4
              max_room_size: 8
              pit_chance: 0
              partition_gate_chance: 0
            """)
        } throws: { error in
            guard let error = error as? WorldSeedError,
                  case .unsupportedGenerationAlgorithm(let name) = error else {
                return false
            }
            return name == "cellular_automata"
        }
    }

    @Test func decodesLetterSpriteSet() throws {
        let level = try LevelConfig.decode(from: """
        name: Tatooine
        width: 20
        height: 20
        algorithm: rooms_doors
        room_count: 5
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
        #expect(level.music == "level")
        #expect(level.musicCue == .track("level"))
        #expect(level.gameMusic.combatCue == .track("combat"))
        #expect(level.gameMusic.pitCue == .track("pit"))
        #expect(level.gameMusic.gateCue == .track("gate"))
    }

    @Test func childCanOverrideGameMusicKeys() throws {
        let child = """
        inherits: base_level
        name: Level 1
        game_music:
          combat: combat_alt
          gate: silence
        """
        let level = try LevelConfig.decode(
            from: child,
            parents: ["base_level": Self.baseLevelYAML]
        )
        #expect(level.gameMusic.combat == "combat_alt")
        #expect(level.gameMusic.gateCue == .silence)
        #expect(level.gameMusic.pit == "pit")
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
        #expect(levels.map { $0.sprite?.root } == levels.map { "Levels/\($0.resourceName)" })

        let tython = try LevelConfig.loadFromBundle(
            named: "1-tython",
            subdirectory: LevelCatalog.subdirectory
        )
        #expect(tython.name == "Tython")
        #expect(tython.order == 1)
        #expect(tython.color == "#2E7D32")
        #expect(tython.sprite?.root == "Levels/1-tython")
        #expect(tython.sprite?.chromaKey == "#000000")
        #expect(tython.sprite?.chromaKeyTolerance == 2)
        #expect(tython.enemies?.types == ["dino", "treant"])
        #expect(tython.width == 20)
        #expect(tython.roomCount == 5)
        #expect(tython.combatLetterSpawnRate == 0.7)
        #expect(tython.combatLetterCase == .lower)
    }

    @Test func decodesCombatLetterSpawnRateAndCase() throws {
        let level = try LevelConfig.decode(
            from: """
            inherits: base_level
            name: Level 1
            combat_letter_spawn_rate: 0.5
            combat_letter_case: both
            """,
            parents: ["base_level": Self.baseLevelYAML]
        )
        #expect(level.combatLetterSpawnRate == 0.5)
        #expect(level.combatLetterCase == .both)
    }

    @Test func rejectsInvalidCombatLetterSpawnRate() throws {
        #expect(throws: WorldSeedError.invalidCombatLetterSpawnRate(0)) {
            try LevelConfig.decode(
                from: """
                inherits: base_level
                name: Level 1
                combat_letter_spawn_rate: 0
                """,
                parents: ["base_level": Self.baseLevelYAML]
            )
        }
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
              root: Levels/1-tython
              chroma: black_soft
              animations:
                idle:
                  sheet: 3-ilum
                  atlas: 3-ilum-atlas
            """,
            parents: ["base_level": Self.baseLevelYAML]
        )
        #expect(level.sprite?.root == "Levels/1-tython")
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
        room:
          min_room_size: 4
          max_room_size: 8
          pit_chance: 0
          partition_gate_chance: 0
        gate:
          fx: { opened: sfx_gate_opened }
          minigames:
            - type: spelling
              words: [CAT, Dog]
        """
        let level = try LevelConfig.decode(from: yaml)
        #expect(level.gate.minigameChance == 0.6)
        guard case .spelling(let spelling) = level.gate.minigames.first else {
            Issue.record("expected spelling minigame")
            return
        }
        #expect(spelling.wordIDs == ["cat", "dog"])
        #expect(spelling.words.map(\.word) == ["cat", "dog"])
        #expect(spelling.words.map(\.spelling) == ["sfx_word_cat", "sfx_word_dog"])
        #expect(spelling.words[0].progressiveTrack(forPrefix: "ca") == "sfx_word_cat_ca")
    }

    @Test func decodesGateMinigameChanceFromYAML() throws {
        let yaml = """
        name: Level 1
        width: 20
        height: 20
        algorithm: rooms_doors
        room_count: 4
        room:
          min_room_size: 4
          max_room_size: 8
          pit_chance: 0
          partition_gate_chance: 0
        gate:
          fx: { opened: sfx_gate_opened }
          minigame_chance: 0.25
          minigames:
            - type: spelling
              words: [cat]
        """
        let level = try LevelConfig.decode(from: yaml)
        #expect(level.gate.minigameChance == 0.25)
    }

    @Test func rejectsInvalidGateMinigameChance() throws {
        let yaml = """
        name: Level
        width: 10
        height: 10
        algorithm: rooms_doors
        room_count: 2
        room:
          min_room_size: 4
          max_room_size: 12
          pit_chance: 0.0
          partition_gate_chance: 0
        gate:
          fx: { opened: sfx_gate_opened }
          minigame_chance: 1.5
          minigames:
            - type: spelling
              words: [cat]
        """

        #expect(throws: WorldSeedError.invalidGateMinigameChance(1.5)) {
            try LevelConfig.decode(from: yaml)
        }
    }

    @Test func inheritsGateConfigFromBase() throws {
        let catalog = try WordCatalog.decode(from: """
        words:
          moon:
            sfx: sfx_word_moon
            progressive:
              m: sfx_word_moon_m
              mo: sfx_word_moon_mo
              moo: sfx_word_moon_moo
              moon: sfx_word_moon_moon
          sun:
            sfx: sfx_word_sun
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
        #expect(spelling.words.map(\.word) == ["moon", "sun"])
    }

    @Test func childCanOverrideInheritedGateWordIDs() throws {
        let catalog = try WordCatalog.decode(from: """
        words:
          moon:
            sfx: sfx_word_moon
            progressive:
              m: sfx_word_moon_m
              mo: sfx_word_moon_mo
              moo: sfx_word_moon_moo
              moon: sfx_word_moon_moon
          nova:
            sfx: sfx_word_nova
            progressive:
              n: sfx_word_nova_n
              no: sfx_word_nova_no
              nov: sfx_word_nova_nov
              nova: sfx_word_nova_nova
          beam:
            sfx: sfx_word_beam
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
              words: [moon]
        """
        let child = """
        inherits: base_level
        name: Level 1
        gate:
          minigames:
            - type: spelling
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
        #expect(spelling.words.map(\.word) == ["beam", "nova"])
        #expect(spelling.words.map(\.spelling) == [
            "sfx_word_beam",
            "sfx_word_nova",
        ])
    }

    @Test func rejectsEmptyGateSpellingWords() {
        let yaml = """
        name: Level 1
        width: 20
        height: 20
        algorithm: rooms_doors
        room_count: 4
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
        #expect(tython.gate.fx.trackID(for: "opened") == "gate-open")
        #expect(tython.gate.minigameChance == 1.0)
        #expect(!tython.gate.minigames.isEmpty)
        let wordPlugConfigs = tython.gate.minigames.compactMap { minigame -> GateWordPlugConfig? in
            if case .wordPlug(let c) = minigame { return c }
            return nil
        }
        #expect(!wordPlugConfigs.isEmpty)
        let wordPlug = wordPlugConfigs[0]
        #expect(wordPlug.wordCountMin == 2)
        #expect(wordPlug.wordCountMax == 2)
        #expect(wordPlug.words.map(\.word).contains("star"))
        #expect(wordPlug.words.contains {
            $0.word == "cat"
                && $0.spelling == "sfx_word_cat"
                && $0.progressiveTrack(forPrefix: "ca") == "sfx_word_cat_ca"
        })
    }

    /// First `type: spelling` entry in a level's pit config.
    private func pitSpelling(_ level: LevelConfig) throws -> PitPuzzleConfig {
        for minigame in level.pit.minigames {
            if case .spelling(let config) = minigame { return config }
        }
        Issue.record("expected a pit spelling entry")
        throw WorldSeedError.decodeFailed("missing pit spelling entry")
    }

    @Test func bundleBaseLevelProvidesPitDefaults() throws {
        let tython = try LevelConfig.loadFromBundle(
            named: "1-tython",
            subdirectory: LevelCatalog.subdirectory
        )
        #expect(tython.pit.fx.trackID(for: "win") == nil)
        #expect(tython.pit.fx.trackID(for: "lose") == "pit-falling")
        #expect(tython.pit.fx.trackID(for: "jump") == "pit-jump")
        let spelling = try pitSpelling(tython)
        #expect(spelling.numPaddingLetters == 6)
        #expect(spelling.words.map(\.word) == ["cat", "dog", "star"])
        #expect(spelling.words.contains {
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
        room:
          min_room_size: 4
          max_room_size: 8
          pit_chance: 0
          partition_gate_chance: 0
        pit:
          fx: { win: sfx_pit_win_alt, lose: sfx_pit_lose_alt }
          minigames:
            - type: spelling
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
        room:
          min_room_size: 4
          max_room_size: 8
          pit_chance: 0
        pit:
          minigames:
            - type: spelling
              words: [star, car]
        """
        let level = try LevelConfig.decode(from: yaml)
        let spelling = try pitSpelling(level)
        #expect(spelling.words.map(\.word) == ["car", "star"])
    }

    @Test func rejectsEmptyPitWords() {
        let yaml = """
        name: Level 1
        width: 20
        height: 20
        algorithm: rooms_doors
        room_count: 4
        room:
          min_room_size: 4
          max_room_size: 8
          pit_chance: 0
        pit:
          minigames:
            - type: spelling
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
        room:
          min_room_size: 4
          max_room_size: 8
          pit_chance: 0
        pit:
          minigames:
            - type: spelling
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

    @Test func rejectsInvalidGateLetterMatchLetterCountRange() {
        let yaml = """
        name: Level 1
        width: 20
        height: 20
        algorithm: rooms_doors
        room_count: 4
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

    @Test func bundleBaseLevelProvidesGateWordPlugDefaults() throws {
        let tython = try LevelConfig.loadFromBundle(
            named: "1-tython",
            subdirectory: LevelCatalog.subdirectory
        )
        let wordPlugConfigs = tython.gate.minigames.compactMap { minigame -> GateWordPlugConfig? in
            if case .wordPlug(let c) = minigame { return c }
            return nil
        }
        #expect(!wordPlugConfigs.isEmpty)
        let wp = wordPlugConfigs[0]
        #expect(wp.wordCountMin == 2)
        #expect(wp.wordCountMax == 2)
        #expect(wp.words.map(\.word) == [
            "bath", "book", "cat", "dance", "dog", "lightbulb", "star", "wand",
        ])
        #expect(tython.artifact == "leaf.fill")
    }

    @Test func decodesGateWordPlugMinigame() throws {
        let yaml = """
        name: Level 1
        width: 20
        height: 20
        algorithm: rooms_doors
        room_count: 4
        room:
          min_room_size: 4
          max_room_size: 8
          pit_chance: 0
          partition_gate_chance: 0
        gate:
          fx: { opened: sfx_gate_opened }
          minigames:
            - type: word_plug
              word_count_min: 3
              word_count_max: 6
              words: [cat, dog]
        """
        let level = try LevelConfig.decode(from: yaml)
        guard case .wordPlug(let wp) = level.gate.minigames.first else {
            Issue.record("expected word_plug minigame")
            return
        }
        #expect(wp.wordCountMin == 3)
        #expect(wp.wordCountMax == 6)
        #expect(wp.words.map(\.word) == ["cat", "dog"])
        #expect(!wp.letters.isEmpty)
    }

    @Test func acceptsNonMultipleOfThreeGateWordPlugWordCount() throws {
        let yaml = """
        name: Level 1
        width: 20
        height: 20
        algorithm: rooms_doors
        room_count: 4
        room:
          min_room_size: 4
          max_room_size: 8
          pit_chance: 0
          partition_gate_chance: 0
        gate:
          fx: { opened: sfx_gate_opened }
          minigames:
            - type: word_plug
              word_count_min: 2
              word_count_max: 4
              words: [cat, dog]
        """
        let level = try LevelConfig.decode(from: yaml)
        guard case .wordPlug(let wp) = level.gate.minigames.first else {
            Issue.record("expected word_plug minigame")
            return
        }
        #expect(wp.wordCountMin == 2)
        #expect(wp.wordCountMax == 4)
    }

    @Test func rejectsTooManyGateWordPlugWords() {
        let yaml = """
        name: Level 1
        width: 20
        height: 20
        algorithm: rooms_doors
        room_count: 4
        room:
          min_room_size: 4
          max_room_size: 8
          pit_chance: 0
          partition_gate_chance: 0
        gate:
          fx: { opened: sfx_gate_opened }
          minigames:
            - type: word_plug
              word_count_min: 3
              word_count_max: 12
              words: [cat, dog]
        """
        #expect(throws: WorldSeedError.invalidGateWordPlugWordCountRange(min: 3, max: 12)) {
            try LevelConfig.decode(from: yaml)
        }
    }

    @Test func rejectsUnknownGateWordPlugWordID() {
        let yaml = """
        name: Level 1
        width: 20
        height: 20
        algorithm: rooms_doors
        room_count: 4
        room:
          min_room_size: 4
          max_room_size: 8
          pit_chance: 0
          partition_gate_chance: 0
        gate:
          fx: { opened: sfx_gate_opened }
          minigames:
            - type: word_plug
              words: [not_a_real_word]
        """
        #expect(throws: WorldSeedError.invalidGateWords) {
            try LevelConfig.decode(from: yaml)
        }
    }

    // MARK: - combat:

    /// Minimal level body the combat tests append a `combat:` block to.
    private static let combatLevelPrefix = """
    name: Level 1
    width: 20
    height: 20
    algorithm: rooms_doors
    room_count: 4
    room:
      min_room_size: 4
      max_room_size: 8
      pit_chance: 0
      partition_gate_chance: 0

    """

    @Test func defaultsToSlashOnlyWhenCombatBlockOmitted() throws {
        let level = try LevelConfig.decode(from: Self.combatLevelPrefix)
        #expect(level.combat == CombatConfig.fallback)
        #expect(level.combat.minigames.map(\.kind) == [.slash])
    }

    @Test func decodesCombatMinigamesFromYAML() throws {
        let level = try LevelConfig.decode(from: Self.combatLevelPrefix + """
        combat:
          minigames:
            - type: slash
              weight: 0.0
            - type: deflect
              weight: 1.0
              monster_hp: 4
              orb_travel_seconds: 2.5
              letters: [C, a, b]
        """)

        #expect(level.combat.minigames.map(\.kind) == [.slash, .deflect])
        guard case .slash(let slash) = level.combat.minigames[0] else {
            Issue.record("expected a slash entry first")
            return
        }
        #expect(slash.weight == 0)

        guard case .deflect(let deflect) = level.combat.minigames[1] else {
            Issue.record("expected a deflect entry second")
            return
        }
        #expect(deflect.weight == 1)
        #expect(deflect.monsterHP == 4)
        #expect(deflect.orbTravelSeconds == 2.5)
        #expect(deflect.letterIDs == ["c", "a", "b"])
        // Ring order is positional (left to right), so YAML order must survive decode.
        #expect(deflect.letters.map(\.letter) == ["c", "a", "b"])
        #expect(deflect.letters.map(\.name) == [
            "sfx_letter_c_name",
            "sfx_letter_a_name",
            "sfx_letter_b_name",
        ])
    }

    @Test func deflectFallsBackToDefaultHPTravelAndLetters() throws {
        let level = try LevelConfig.decode(from: Self.combatLevelPrefix + """
        combat:
          minigames:
            - type: deflect
        """)
        guard case .deflect(let deflect) = level.combat.minigames.first else {
            Issue.record("expected a deflect entry")
            return
        }
        #expect(deflect.weight == 1)
        #expect(deflect.monsterHP == CombatDeflectConfig.defaultMonsterHP)
        #expect(deflect.orbTravelSeconds == CombatDeflectConfig.defaultOrbTravelSeconds)
        #expect(deflect.letters.count == CombatDeflectConfig.ringCount)
    }

    @Test func inheritsCombatBlockFromBase() throws {
        let base = Self.combatLevelPrefix + """
        combat:
          minigames:
            - type: deflect
              weight: 1.0
              monster_hp: 7
              letters: [a, b, c]
        """
        let level = try LevelConfig.decode(
            from: "inherits: base_level\nname: Level 2",
            parents: ["base_level": base]
        )
        guard case .deflect(let deflect) = level.combat.minigames.first else {
            Issue.record("expected an inherited deflect entry")
            return
        }
        #expect(deflect.monsterHP == 7)
        #expect(deflect.letters.map(\.letter) == ["a", "b", "c"])
    }

    @Test func pickMinigameNeverChoosesAZeroWeightEntry() throws {
        let config = CombatConfig(minigames: [
            .slash(CombatSlashConfig(weight: 0)),
            .deflect(CombatDeflectConfig(weight: 1)),
        ])
        var rng = CombatSeededGenerator(seed: 5)
        for _ in 0..<200 {
            #expect(try config.pickMinigame(using: &rng).kind == .deflect)
        }
    }

    @Test func pickMinigameEventuallyChoosesBothWhenBothAreWeighted() throws {
        let config = CombatConfig(minigames: [
            .slash(CombatSlashConfig(weight: 1)),
            .deflect(CombatDeflectConfig(weight: 1)),
        ])
        var rng = CombatSeededGenerator(seed: 11)
        var seen = Set<CombatMinigameKind>()
        for _ in 0..<200 {
            seen.insert(try config.pickMinigame(using: &rng).kind)
        }
        #expect(seen == Set(CombatMinigameKind.allCases))
    }

    @Test func pickMinigameFallsBackToTheFirstEntryWhenAllWeightsAreZero() throws {
        let config = CombatConfig(minigames: [
            .slash(CombatSlashConfig(weight: 0)),
            .deflect(CombatDeflectConfig(weight: 0)),
        ])
        var rng = CombatSeededGenerator(seed: 3)
        #expect(try config.pickMinigame(using: &rng).kind == .slash)
    }

    @Test func pickMinigameThrowsWhenMinigamesEmpty() {
        let config = CombatConfig(minigames: [])
        var rng = CombatSeededGenerator(seed: 3)
        #expect(throws: WorldSeedError.self) {
            try config.pickMinigame(using: &rng)
        }
    }

    @Test func pickGateMinigameKindThrowsWhenMinigamesEmpty() {
        let config = GateConfig(fx: .empty, minigames: [])
        var rng = CombatSeededGenerator(seed: 3)
        #expect(throws: WorldSeedError.self) {
            try config.pickMinigameKind(using: &rng)
        }
    }

    @Test func rejectsUnknownCombatMinigameType() {
        #expect {
            try LevelConfig.decode(from: Self.combatLevelPrefix + """
            combat:
              minigames:
                - type: parry
            """)
        } throws: { error in
            guard let error = error as? WorldSeedError,
                  case .decodeFailed = error else { return false }
            return true
        }
    }

    @Test func rejectsEmptyCombatMinigames() {
        #expect {
            try LevelConfig.decode(from: Self.combatLevelPrefix + """
            combat:
              minigames: []
            """)
        } throws: { error in
            guard let error = error as? WorldSeedError,
                  case .decodeFailed = error else { return false }
            return true
        }
    }

    @Test func rejectsNegativeCombatMinigameWeight() {
        #expect(throws: WorldSeedError.invalidCombatMinigameWeight(-1)) {
            try LevelConfig.decode(from: Self.combatLevelPrefix + """
            combat:
              minigames:
                - type: deflect
                  weight: -1.0
            """)
        }
    }

    @Test func rejectsDuplicateCombatMinigameTypes() {
        #expect {
            try LevelConfig.decode(from: Self.combatLevelPrefix + """
            combat:
              minigames:
                - type: deflect
                - type: deflect
            """)
        } throws: { error in
            guard let error = error as? WorldSeedError,
                  case .decodeFailed = error else { return false }
            return true
        }
    }

    @Test func rejectsNonPositiveCombatMonsterHP() {
        #expect(throws: WorldSeedError.invalidCombatMonsterHP(0)) {
            try LevelConfig.decode(from: Self.combatLevelPrefix + """
            combat:
              minigames:
                - type: deflect
                  monster_hp: 0
            """)
        }
    }

    @Test func rejectsNonPositiveCombatOrbTravelSeconds() {
        #expect(throws: WorldSeedError.invalidCombatOrbTravelSeconds(0)) {
            try LevelConfig.decode(from: Self.combatLevelPrefix + """
            combat:
              minigames:
                - type: deflect
                  orb_travel_seconds: 0
            """)
        }
    }

    @Test func rejectsUnknownCombatDeflectLetterID() {
        #expect(throws: WorldSeedError.invalidCombatDeflectLetters) {
            try LevelConfig.decode(from: Self.combatLevelPrefix + """
            combat:
              minigames:
                - type: deflect
                  letters: [a, b, not_a_letter]
            """)
        }
    }

    @Test func rejectsCombatDeflectLetterCountOutsideTwoToSix() {
        #expect(throws: WorldSeedError.invalidCombatDeflectLetters) {
            try LevelConfig.decode(from: Self.combatLevelPrefix + """
            combat:
              minigames:
                - type: deflect
                  letters: [a]
            """)
        }
        #expect(throws: WorldSeedError.invalidCombatDeflectLetters) {
            try LevelConfig.decode(from: Self.combatLevelPrefix + """
            combat:
              minigames:
                - type: deflect
                  letters: [a, b, c, d, e, f, g]
            """)
        }
    }

    @Test func acceptsCombatDeflectLetterCountsFromTwoToSix() throws {
        let level = try LevelConfig.decode(from: Self.combatLevelPrefix + """
        combat:
          minigames:
            - type: deflect
              letters: [a, b, c, d]
        """)
        guard case .deflect(let deflect) = level.combat.minigames.first else {
            Issue.record("expected a deflect entry")
            return
        }
        #expect(deflect.letters.map(\.letter) == ["a", "b", "c", "d"])
    }

    @Test func rejectsDuplicateCombatDeflectLetters() {
        #expect(throws: WorldSeedError.invalidCombatDeflectLetters) {
            try LevelConfig.decode(from: Self.combatLevelPrefix + """
            combat:
              minigames:
                - type: deflect
                  letters: [a, a, b]
            """)
        }
    }

    @Test func bundleDefaultsProvideDeflectCombatConfig() throws {
        let tython = try LevelConfig.loadFromBundle(
            named: "1-tython",
            subdirectory: LevelCatalog.subdirectory
        )
        guard case .deflect(let deflect) = tython.combat.minigame(for: .deflect) else {
            Issue.record("expected the bundled defaults to define a deflect minigame")
            return
        }
        #expect(deflect.monsterHP >= 1)
        #expect(deflect.orbTravelSeconds > 0)
        #expect(deflect.letters.map(\.letter) == ["a", "b", "c", "d"])
    }

    @Test func decodesTopLevelLetterSoundRepeatSeconds() throws {
        let yaml = """
        name: Level 1
        width: 20
        height: 20
        algorithm: rooms_doors
        room_count: 4
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

    // MARK: - pit.minigames:

    /// Minimal level body the pit minigame tests append a `pit:` block to.
    private static let pitLevelPrefix = """
    name: Level 1
    width: 20
    height: 20
    algorithm: rooms_doors
    room_count: 4
    room:
      min_room_size: 4
      max_room_size: 8
      pit_chance: 0
      partition_gate_chance: 0

    """

    @Test func defaultsToSpellingOnlyWhenPitBlockOmitted() throws {
        let level = try LevelConfig.decode(from: Self.pitLevelPrefix)
        #expect(level.pit.fx.trackID(for: "jump") == "pit-jump")
        #expect(level.pit.fx.trackID(for: "lose") == "pit-falling")
        #expect(level.pit.minigames.map(\.kind) == [.spelling])
        let spelling = try pitSpelling(level)
        #expect(spelling.weight == 1)
        #expect(!spelling.words.isEmpty)
    }

    @Test func decodesPitMinigamesFromYAML() throws {
        let level = try LevelConfig.decode(from: Self.pitLevelPrefix + """
        pit:
          fx: { lose: pit-falling, jump: pit-jump }
          minigames:
            - type: spelling
              weight: 0.0
              num_padding_letters: 6
              words: [cat, dog, star]
            - type: bridge
              weight: 1.0
              min_words: 2
              max_words: 4
              words: [car, dog, trash, sun, star, book]
        """)
        #expect(level.pit.fx.trackID(for: "jump") == "pit-jump")
        #expect(level.pit.minigames.map(\.kind) == [.spelling, .bridge])
        if case .spelling(let spelling) = level.pit.minigames[0] {
            #expect(spelling.weight == 0)
            #expect(spelling.numPaddingLetters == 6)
            #expect(spelling.words.map(\.word) == ["cat", "dog", "star"])
        } else {
            Issue.record("expected spelling entry")
        }
        if case .bridge(let bridge) = level.pit.minigames[1] {
            #expect(bridge.weight == 1)
            #expect(bridge.minWords == 2)
            #expect(bridge.maxWords == 4)
            #expect(bridge.wordIDs == ["car", "dog", "trash", "sun", "star", "book"])
            #expect(Set(bridge.words.map(\.word)) == Set(["book", "car", "dog", "star", "sun", "trash"]))
            #expect(bridge.words.allSatisfy { ($0.image?.isEmpty == false) })
        } else {
            Issue.record("expected bridge entry")
        }
    }

    @Test func bridgeFallsBackToDefaultMinMaxAndWords() throws {
        let level = try LevelConfig.decode(from: Self.pitLevelPrefix + """
        pit:
          minigames:
            - type: bridge
              weight: 1
        """)
        guard case .bridge(let bridge) = level.pit.minigames.first else {
            Issue.record("expected bridge entry")
            return
        }
        #expect(bridge.minWords == PitBridgeConfig.defaultMinWords)
        #expect(bridge.maxWords == PitBridgeConfig.defaultMaxWords)
        #expect(bridge.wordIDs == PitBridgeConfig.defaultWordIDs)
        #expect(Set(bridge.words.map(\.word)) == Set(PitBridgeConfig.defaultWordIDs))
    }

    @Test func inheritsPitBlockFromBase() throws {
        let base = Self.baseLevelYAMLWithoutPuzzles + """

        pit:
          fx: { lose: pit-falling, jump: pit-jump }
          minigames:
            - type: bridge
              weight: 1
              min_words: 2
              max_words: 3
              words: [car, dog, trash, sun]
        """
        let child = """
        inherits: base_level
        name: Child
        """
        let level = try LevelConfig.decode(
            from: child,
            parents: ["base_level": base]
        )
        guard case .bridge(let bridge) = level.pit.minigames.first else {
            Issue.record("expected an inherited bridge entry")
            return
        }
        #expect(bridge.maxWords == 3)
        #expect(bridge.wordIDs == ["car", "dog", "trash", "sun"])
        #expect(Set(bridge.words.map(\.word)) == Set(["car", "dog", "sun", "trash"]))
    }

    @Test func childCanOverrideInheritedPitMinigames() throws {
        let base = Self.baseLevelYAMLWithoutPuzzles + """

        pit:
          minigames:
            - type: spelling
              words: [cat]
        """
        let child = """
        inherits: base_level
        name: Child
        pit:
          minigames:
            - type: bridge
              words: [car, dog, trash, sun, star, book]
        """
        let level = try LevelConfig.decode(
            from: child,
            parents: ["base_level": base]
        )
        #expect(level.pit.minigames.map(\.kind) == [.bridge])
    }

    @Test func pickPitMinigameNeverChoosesAZeroWeightEntry() throws {
        let config = PitConfig(
            fx: .empty,
            minigames: [
                .spelling(PitPuzzleConfig(weight: 0, words: PitPuzzleConfig.fallback.words)),
                .bridge(PitBridgeConfig(weight: 1)),
            ]
        )
        var rng = PitSeededGenerator(seed: 5)
        for _ in 0..<200 {
            #expect(try config.pickMinigame(using: &rng).kind == .bridge)
        }
    }

    @Test func pickPitMinigameEventuallyChoosesBothWhenBothAreWeighted() throws {
        let config = PitConfig(
            fx: .empty,
            minigames: [
                .spelling(PitPuzzleConfig(weight: 1, words: PitPuzzleConfig.fallback.words)),
                .bridge(PitBridgeConfig(weight: 1)),
            ]
        )
        var rng = PitSeededGenerator(seed: 11)
        var seen = Set<PitMinigameKind>()
        for _ in 0..<200 {
            seen.insert(try config.pickMinigame(using: &rng).kind)
        }
        #expect(seen == Set(PitMinigameKind.allCases))
    }

    @Test func pickPitMinigameFallsBackToTheFirstEntryWhenAllWeightsAreZero() throws {
        let config = PitConfig(
            fx: .empty,
            minigames: [
                .spelling(PitPuzzleConfig(weight: 0, words: PitPuzzleConfig.fallback.words)),
                .bridge(PitBridgeConfig(weight: 0)),
            ]
        )
        var rng = PitSeededGenerator(seed: 3)
        #expect(try config.pickMinigame(using: &rng).kind == .spelling)
    }

    @Test func pickPitMinigameThrowsWhenMinigamesEmpty() {
        let config = PitConfig(fx: .empty, minigames: [])
        var rng = PitSeededGenerator(seed: 3)
        #expect(throws: WorldSeedError.self) {
            try config.pickMinigame(using: &rng)
        }
    }

    @Test func rejectsUnknownPitMinigameType() {
        #expect {
            try LevelConfig.decode(from: Self.pitLevelPrefix + """
            pit:
              minigames:
                - type: hopscotch
            """)
        } throws: { error in
            guard let error = error as? WorldSeedError,
                  case .decodeFailed(let message) = error else {
                return false
            }
            return message.contains("Unknown pit minigame type")
        }
    }

    @Test func rejectsDuplicatePitMinigameTypes() {
        #expect {
            try LevelConfig.decode(from: Self.pitLevelPrefix + """
            pit:
              minigames:
                - type: bridge
                - type: bridge
                  weight: 2
            """)
        } throws: { error in
            guard let error = error as? WorldSeedError,
                  case .decodeFailed(let message) = error else {
                return false
            }
            return message.contains("duplicate type")
        }
    }

    @Test func rejectsNegativePitMinigameWeight() {
        #expect(throws: WorldSeedError.invalidPitMinigameWeight(-1)) {
            try LevelConfig.decode(from: Self.pitLevelPrefix + """
            pit:
              minigames:
                - type: bridge
                  weight: -1
            """)
        }
    }

    @Test func rejectsInvalidPitBridgeWordRange() {
        #expect(throws: WorldSeedError.invalidPitBridgeWordRange(min: 0, max: 4)) {
            try LevelConfig.decode(from: Self.pitLevelPrefix + """
            pit:
              minigames:
                - type: bridge
                  min_words: 0
                  max_words: 4
            """)
        }
        #expect(throws: WorldSeedError.invalidPitBridgeWordRange(min: 5, max: 2)) {
            try LevelConfig.decode(from: Self.pitLevelPrefix + """
            pit:
              minigames:
                - type: bridge
                  min_words: 5
                  max_words: 2
                  words: [car, dog, trash, sun, star, book]
            """)
        }
    }

    @Test func rejectsPitBridgePoolSmallerThanMaxWords() {
        #expect(throws: WorldSeedError.invalidPitBridgeWords) {
            try LevelConfig.decode(from: Self.pitLevelPrefix + """
            pit:
              minigames:
                - type: bridge
                  min_words: 2
                  max_words: 4
                  words: [car, dog]
            """)
        }
    }

    @Test func rejectsPitBridgeDuplicateOrUnknownWords() {
        #expect(throws: WorldSeedError.invalidPitBridgeWords) {
            try LevelConfig.decode(from: Self.pitLevelPrefix + """
            pit:
              minigames:
                - type: bridge
                  min_words: 2
                  max_words: 2
                  words: [car, car]
            """)
        }
        #expect(throws: WorldSeedError.invalidPitBridgeWords) {
            try LevelConfig.decode(from: Self.pitLevelPrefix + """
            pit:
              minigames:
                - type: bridge
                  min_words: 1
                  max_words: 1
                  words: [a]
            """)
        }
    }

    @Test func rejectsPitBridgeWordsWithoutImages() {
        #expect(throws: WorldSeedError.invalidPitBridgeWords) {
            try LevelConfig.decode(from: Self.pitLevelPrefix + """
            pit:
              minigames:
                - type: bridge
                  min_words: 1
                  max_words: 1
                  words: [gate]
            """)
        }
    }

    @Test func bundleDefaultsProvideBridgePitConfig() throws {
        let tython = try LevelConfig.loadFromBundle(
            named: "1-tython",
            subdirectory: LevelCatalog.subdirectory
        )
        #expect(tython.pit.minigames.map(\.kind) == [.spelling, .bridge])
        if case .spelling(let spelling) = tython.pit.minigames[0] {
            #expect(spelling.weight == 0)
        } else {
            Issue.record("expected spelling entry")
        }
        if case .bridge(let bridge) = tython.pit.minigames[1] {
            #expect(bridge.weight == 1)
            #expect(bridge.wordIDs == ["car", "dog", "trash", "sun", "star", "book"])
            #expect(Set(bridge.words.map(\.word)) == Set(["book", "car", "dog", "star", "sun", "trash"]))
        } else {
            Issue.record("expected bridge entry")
        }
    }

    @Test func floorCohesionDefaultsAndRejectsOutOfRange() throws {
        let tython = try LevelConfig.loadFromBundle(
            named: "1-tython",
            subdirectory: LevelCatalog.subdirectory
        )
        #expect(tython.floor.cohesion == 0.75)
        #expect(LevelConfig.fallbackFloor.cohesion == 0.75)

        #expect(throws: WorldSeedError.invalidFloorCohesion(1.5)) {
            try GenerationParamsValidator.validate(
                algorithm: "rooms_doors",
                width: 100,
                height: 100,
                room: LevelConfig.RoomParams(
                    minRoomSize: 4,
                    maxRoomSize: 12,
                    pitChance: 0.2,
                    pitMeanSize: 2,
                    pitMaxSize: 5
                ),
                floorSet: "1-tython",
                decorProb: 0.06,
                cohesion: 1.5,
                enemies: nil,
                pickups: nil
            )
        }
    }
}

