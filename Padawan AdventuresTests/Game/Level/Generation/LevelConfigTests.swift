import Foundation
import Testing
import Yams
@testable import Padawan_Adventures

struct LevelConfigTests {

    /// In-memory vocabulary catalog for unit tests that do not load shipped levels.
    /// Pads with imaged Level-1-style entries so omitted `pit:` fallbacks still resolve.
    private static func vocabCatalog(
        words: [String],
        graphemes: [String]? = nil,
        order: Int = 1,
        supportOmittedPit: Bool = true
    ) -> LevelVocabularyCatalog {
        var letters = graphemes
            ?? Array(Set(words.flatMap { Array($0) }.map(String.init))).sorted()
        var wordIDs = words
        if supportOmittedPit {
            for grapheme in ["a", "b", "c", "d", "e", "f", "s", "t", "n", "p", "i"]
            where !letters.contains(grapheme) {
                letters.append(grapheme)
            }
            for word in ["sat", "sit", "pat"] where !wordIDs.contains(word) {
                wordIDs.append(word)
            }
        }
        return LevelVocabularyCatalog(specsByOrder: [
            order: LevelVocabularySpec(graphemes: letters, words: wordIDs),
        ])
    }

    private static let baseLevelYAML = """
        name: Level
        world:
          music: level
          width_tiles: 100
          height_tiles: 100
          room_count: 100
          room:
            min_size_tiles: 4
            max_size_tiles: 12
            pit_probability: 0.2
            pit_mean_size_tiles: 2
            pit_max_size_tiles: 5
          enemies:
            type: spider
            spawn_probability_per_room: 0.8
          pickups:
            health:
              spawn_probability_per_room: 0.8
            energy:
              spawn_probability_per_room: 0.8
        combat:
          music: combat
          minigames:
            - type: grapheme-sound-combat
        gate:
          music: gate
          fx: { opened: sfx_gate_opened }
          minigames:
            - type: sound-out-word-gate
              words: [cat, dog, sat]
              music: gate
            - type: grapheme-sound-gate
              graphemes: [a, b, c, d, e, f, g, h]
              music: gate
        pit:
          music: pit
          minigames:
            - type: sound-out-word-pit
              words: [cat, dog, sun, sat]
        """

    /// Base YAML without gate/pit blocks so inheritance tests can append their own.
    private static let baseLevelYAMLWithoutPuzzles = """
        name: Level
        world:
          music: level
          width_tiles: 100
          height_tiles: 100
          room_count: 100
          room:
            min_size_tiles: 4
            max_size_tiles: 12
            pit_probability: 0.2
            pit_mean_size_tiles: 2
            pit_max_size_tiles: 5
          enemies:
            type: spider
            spawn_probability_per_room: 0.8
          pickups:
            health:
              spawn_probability_per_room: 0.8
            energy:
              spawn_probability_per_room: 0.8
        combat:
          music: combat
          minigames:
            - type: grapheme-sound-combat
        """

    @Test func decodesLevelYAML() throws {
        let yaml = """
        name: Level 1
        world:
          width_tiles: 100
          height_tiles: 100
          room_count: 100
          room:
            min_size_tiles: 4
            max_size_tiles: 12
            pit_probability: 0.2
            pit_mean_size_tiles: 2
            pit_max_size_tiles: 5
            gate_probability: 0.8
          enemies:
            type: spider
            spawn_probability_per_room: 0.8
          pickups:
            health:
              spawn_probability_per_room: 0.8
            energy:
              spawn_probability_per_room: 0.8
        """
        let level = try LevelConfig.decode(from: yaml)
        #expect(level.name == "Level 1")
        #expect(level.width == 100)
        #expect(level.height == 100)
        #expect(level.roomCount == 100)
        #expect(level.room.minRoomSize == 4)
        #expect(level.room.maxRoomSize == 12)
        #expect(level.room.pitChance == 0.2)
        #expect(level.room.pitMeanSize == 2)
        #expect(level.room.pitMaxSize == 5)
        #expect(level.room.gateProbability == 0.8)
        #expect(level.enemies?.type == "spider")
        #expect(level.enemies?.spawnChancePerRoom == 0.8)
        #expect(level.pickups?.health?.spawnChancePerRoom == 0.8)
        #expect(level.pickups?.energy?.spawnChancePerRoom == 0.8)
        #expect(level.music == nil)
        #expect(level.musicCue == .unchanged)
        #expect(level.artifact == LevelConfig.fallbackArtifact)
        #expect(level.letters.set == LevelConfig.fallbackLetters.set)
    }


    @Test func decodesLetterSpriteSet() throws {
        let level = try LevelConfig.decode(from: """
        name: Tatooine
        world:
          width_tiles: 20
          height_tiles: 20
          room_count: 5
          room:
            min_size_tiles: 4
            max_size_tiles: 12
            pit_probability: 0.2
            pit_mean_size_tiles: 2
            pit_max_size_tiles: 5
            gate_probability: 0.8
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
        #expect(MusicCue.parse(level.combat.music) == .track("combat"))
        #expect(MusicCue.parse(level.pit.music) == .track("pit"))
        #expect(MusicCue.parse(level.gate.music) == .track("gate"))
    }

    @Test func childCanOverrideGameMusicKeys() throws {
        let child = """
        inherits: base_level
        name: Level 1
        combat:
          music: combat_alt
          minigames:
            - type: grapheme-sound-combat
        gate:
          music: silence
          fx: { opened: sfx_gate_opened }
          minigames:
            - type: sound-out-word-gate
              words: [cat, dog, sat]
        """
        let level = try LevelConfig.decode(
            from: child,
            parents: ["base_level": Self.baseLevelYAML]
        )
        #expect(level.combat.music == "combat_alt")
        #expect(MusicCue.parse(level.gate.music) == .silence)
        #expect(level.pit.music == "pit")
    }

    @Test func childCanOverrideMusic() throws {
        let child = """
        inherits: base_level
        name: Level 1
        world:
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
        world:
          width_tiles: 20
          height_tiles: 20
          room_count: 4
          room:
            min_size_tiles: 4
            max_size_tiles: 8
            pit_probability: 0
            gate_probability: 0
        gate:
          fx: { opened: sfx_gate_opened_alt }
          minigames:
            - type: sound-out-word-gate
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
        world:
          room_count: 50
          room:
            pit_probability: 0.9
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
        #expect(level.room.gateProbability == 0.8)
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
        world:
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
        """
        let config = try WorldLoader.decodeConfig(from: yaml)
        #expect(config.seed == nil)
        try config.validate()

        let generation = WorldGenerationConfig.compose(app: config, level: .fallback)
        #expect(generation.world.width == LevelConfig.fallback.width)
        #expect(generation.world.height == LevelConfig.fallback.height)
        #expect(generation.generation == LevelConfig.fallback.generation)
    }

    @Test func deepMergeNestedDictionariesPreferChild() {
        let base: [String: Any] = [
            "room": [
                "pit_probability": 0.2,
                "gate_probability": 0.5,
            ],
            "room_count": 100,
        ]
        let child: [String: Any] = [
            "room": [
                "pit_probability": 0.9,
            ],
            "name": "Level 3",
        ]
        let merged = ConfigStore.deepMerge(base, overwriting: child)
        #expect(merged["name"] as? String == "Level 3")
        #expect(merged["room_count"] as? Int == 100)
        let room = merged["room"] as? [String: Any]
        #expect(room?["pit_probability"] as? Double == 0.9)
        #expect(room?["gate_probability"] as? Double == 0.5)
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
        #expect(tython.width == 28)
        #expect(tython.roomCount == 10)
        guard case .slash(let tythonSlash) = tython.combat.minigames.first else {
            Issue.record("expected slash entry")
            return
        }
        #expect(tythonSlash.minDecoyCount == 2)
        #expect(tythonSlash.maxDecoyCount == 4)
        #expect(tythonSlash.graphemeCase == .lower)
    }

    @Test func decodesCombatDecoyCountAndCase() throws {
        let level = try LevelConfig.decode(
            from: """
            inherits: base_level
            name: Level 1
            combat:
              minigames:
                - type: grapheme-sound-combat
                  min_decoy_count: 3
                  max_decoy_count: 3
                  grapheme_case: both
            """,
            parents: ["base_level": Self.baseLevelYAML]
        )
        guard case .slash(let slash) = level.combat.minigames.first else {
            Issue.record("expected slash entry")
            return
        }
        #expect(slash.minDecoyCount == 3)
        #expect(slash.maxDecoyCount == 3)
        #expect(slash.graphemeCase == .both)
    }

    @Test func rejectsInvalidCombatDecoyCount() throws {
        #expect(throws: WorldSeedError.invalidCombatDecoyCount(min: 4, max: 2)) {
            try LevelConfig.decode(
                from: """
                inherits: base_level
                name: Level 1
                combat:
                  minigames:
                    - type: grapheme-sound-combat
                      min_decoy_count: 4
                      max_decoy_count: 2
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
            world:
              enemies:
                types: [dino, treant]
                spawn_probability_per_room: 0.5
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
            world:
              enemies:
                type: ice_monster
                spawn_probability_per_room: 0.25
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
        world:
          width_tiles: 20
          height_tiles: 20
          room_count: 4
          room:
            min_size_tiles: 4
            max_size_tiles: 8
            pit_probability: 0
            gate_probability: 0
        """)
        #expect(level.gate.minigames.map(\.kind) == GateConfig.fallback.minigames.map(\.kind))
        #expect(level.gate.minigameChance == GateConfig.fallback.minigameChance)
        #expect(!level.gate.minigames.isEmpty)
    }

    @Test func decodesGateSoundOutWordMinigameFromYAML() throws {
        let yaml = """
        name: Level 1
        order: 1
        vocab:
          graphemes: [c, a, t, d, o, g]
          words: [cat, dog]
        world:
          width_tiles: 20
          height_tiles: 20
          room_count: 4
          room:
            min_size_tiles: 4
            max_size_tiles: 8
            pit_probability: 0
            gate_probability: 0
        gate:
          fx: { opened: sfx_gate_opened }
          minigames:
            - type: sound-out-word-gate
        """
        let level = try LevelConfig.decode(
            from: yaml,
            vocabularyCatalog: Self.vocabCatalog(
                words: ["cat", "dog"],
                graphemes: ["c", "a", "t", "d", "o", "g"]
            )
        )
        #expect(level.gate.minigameChance == 0.6)
        guard case .soundOutWord(let soundOutWord) = level.gate.minigames.first else {
            Issue.record("expected sound-out-word minigame")
            return
        }
        #expect(Set(soundOutWord.words.map(\.word)).isSuperset(of: ["cat", "dog"]))
        #expect(soundOutWord.words.contains { $0.word == "cat" && $0.graphemes == ["c", "a", "t"] })
    }

    @Test func decodesGateMinigameChanceFromYAML() throws {
        let yaml = """
        name: Level 1
        world:
          width_tiles: 20
          height_tiles: 20
          room_count: 4
          room:
            min_size_tiles: 4
            max_size_tiles: 8
            pit_probability: 0
            gate_probability: 0
        gate:
          fx: { opened: sfx_gate_opened }
          minigame_probability: 0.25
          minigames:
            - type: sound-out-word-gate
              words: [cat]
        """
        let level = try LevelConfig.decode(from: yaml)
        #expect(level.gate.minigameChance == 0.25)
    }

    @Test func rejectsInvalidGateMinigameChance() throws {
        let yaml = """
        name: Level
        world:
          width_tiles: 10
          height_tiles: 10
          room_count: 2
          room:
            min_size_tiles: 4
            max_size_tiles: 12
            pit_probability: 0.0
            gate_probability: 0
        gate:
          fx: { opened: sfx_gate_opened }
          minigame_probability: 1.5
          minigames:
            - type: sound-out-word-gate
              words: [cat]
        """

        #expect(throws: WorldSeedError.invalidGateMinigameChance(1.5)) {
            try LevelConfig.decode(from: yaml)
        }
    }

    @Test func inheritsGateConfigFromBase() throws {
        // Custom ids for the gate entry, plus the fallback catalog so the omitted
        // pit block (PitConfig.fallback → sound-out-word-pit) can still resolve.
        let custom = try WordCatalog.decode(from: """
        words:
          moon:
            sfx: sfx_word_moon
            graphemes: [m, o, o, n]
          sun:
            sfx: sfx_word_sun
            graphemes: [s, u, n]
        """)
        let catalog = WordCatalog(words: WordCatalog.fallback.words + custom.words)
        let base = Self.baseLevelYAMLWithoutPuzzles + """

        gate:
          fx: { opened: sfx_gate_opened }
          minigames:
            - type: sound-out-word-gate
              words: [moon, sun]
        """
        let child = """
        inherits: base_level
        name: Level 1
        """
        let level = try LevelConfig.decode(
            from: child,
            parents: ["base_level": base],
            wordCatalog: catalog,
            vocabularyCatalog: Self.vocabCatalog(
                words: ["moon", "sun"],
                graphemes: ["m", "o", "n", "s", "u"]
            )
        )
        guard case .soundOutWord(let soundOutWord) = level.gate.minigames.first else {
            Issue.record("expected sound-out-word minigame")
            return
        }
        #expect(Set(soundOutWord.words.map(\.word)).isSuperset(of: ["moon", "sun"]))
    }

    @Test func childCanOverrideInheritedGateWordIDs() throws {
        // Custom ids for the gate entry, plus the fallback catalog so the omitted
        // pit block (PitConfig.fallback → sound-out-word-pit) can still resolve.
        let custom = try WordCatalog.decode(from: """
        words:
          moon:
            sfx: sfx_word_moon
            graphemes: [m, o, o, n]
          nova:
            sfx: sfx_word_nova
            graphemes: [n, o, v, a]
          beam:
            sfx: sfx_word_beam
            graphemes: [b, e, a, m]
        """)
        let catalog = WordCatalog(words: WordCatalog.fallback.words + custom.words)
        let base = Self.baseLevelYAMLWithoutPuzzles + """

        gate:
          fx: { opened: sfx_gate_opened }
          minigames:
            - type: sound-out-word-gate
              words: [moon]
        """
        let child = """
        inherits: base_level
        name: Level 1
        gate:
          minigames:
            - type: sound-out-word-gate
              words: [nova, beam]
        """
        let level = try LevelConfig.decode(
            from: child,
            parents: ["base_level": base],
            wordCatalog: catalog,
            vocabularyCatalog: Self.vocabCatalog(
                words: ["nova", "beam"],
                graphemes: ["n", "o", "v", "a", "b", "e", "m"]
            )
        )
        guard case .soundOutWord(let soundOutWord) = level.gate.minigames.first else {
            Issue.record("expected sound-out-word minigame")
            return
        }
        // Vocabulary now comes from the level pool, not per-minigame `words:`.
        #expect(Set(soundOutWord.words.map(\.word)).isSuperset(of: ["beam", "nova"]))
        #expect(soundOutWord.words.contains { $0.word == "beam" && $0.spelling == "sfx_word_beam" })
        #expect(soundOutWord.words.contains { $0.word == "nova" && $0.spelling == "sfx_word_nova" })
    }

    
    @Test func rejectsEmptyGateSoundOutWordWords() {
        let config = GateSoundOutWordConfig(
            words: [],
            graphemes: GraphemeCatalog.fallback.graphemes
        )
        #expect(throws: WorldSeedError.invalidGateWords) {
            try config.validate()
        }
    }


    @Test func rejectsUnknownGateSoundOutWordWordID() {
        let yaml = """
        name: Level 1
        order: 1
        world:
          width_tiles: 20
          height_tiles: 20
          room_count: 4
          room:
            min_size_tiles: 4
            max_size_tiles: 8
            pit_probability: 0
            gate_probability: 0
        gate:
          fx: { opened: sfx_gate_opened }
          minigames:
            - type: sound-out-word-gate
        """
        #expect(throws: WorldSeedError.invalidGateWords) {
            try LevelConfig.decode(
                from: yaml,
                vocabularyCatalog: Self.vocabCatalog(
                    words: ["not_a_real_word"],
                    graphemes: ["a"]
                )
            )
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
        #expect(wordPlug.words.map(\.word).contains("sat"))
        #expect(wordPlug.words.contains {
            $0.word == "sat"
                && $0.spelling == "sfx_word_sat"
                && $0.graphemes == ["s", "a", "t"]
        })
    }

    /// First `type: sound-out-word-pit` entry in a level's pit config.
    private func pitSoundOutWord(_ level: LevelConfig) throws -> PitSoundOutWordConfig {
        for minigame in level.pit.minigames {
            if case .soundOutWord(let config) = minigame { return config }
        }
        Issue.record("expected a pit sound-out-word entry")
        throw WorldSeedError.decodeFailed("missing pit sound-out-word entry")
    }

    @Test func bundleBaseLevelProvidesPitDefaults() throws {
        let tython = try LevelConfig.loadFromBundle(
            named: "1-tython",
            subdirectory: LevelCatalog.subdirectory
        )
        #expect(tython.pit.fx.trackID(for: "win") == nil)
        #expect(tython.pit.fx.trackID(for: "lose") == nil)
        #expect(tython.pit.fx.trackID(for: "jump") == "pit-jump")
        let soundOut = try pitSoundOutWord(tython)
        #expect(soundOut.choiceCountMin == 3)
        #expect(soundOut.choiceCountMax == 3)
        #expect(soundOut.words.map(\.word) == ["an", "at", "in", "it", "nap", "pan", "pat", "pin", "sat", "sip", "sit", "tap"])
        #expect(soundOut.words.contains {
            $0.word == "sat"
                && $0.spelling == "sfx_word_sat"
                && $0.graphemes == ["s", "a", "t"]
        })
    }

    @Test func decodesOptionalMinigameSoundOverrides() throws {
        let yaml = """
        name: Level 1
        world:
          width_tiles: 20
          height_tiles: 20
          room_count: 4
          room:
            min_size_tiles: 4
            max_size_tiles: 8
            pit_probability: 0
            gate_probability: 0
        pit:
          fx: { win: sfx_pit_win_alt, lose: sfx_pit_lose_alt }
          minigames:
            - type: sound-out-word-pit
              words: [cat]
        gate:
          fx: { opened: sfx_gate_opened }
          minigames:
            - type: sound-out-word-gate
              fx: { win: sfx_gate_win_alt }
              words: [dog]
            - type: grapheme-sound-gate
              fx: { correct: sfx_wall_correct_alt }
              graphemes: [a]
        """
        let level = try LevelConfig.decode(from: yaml)
        #expect(level.pit.fx.trackID(for: "win") == "sfx_pit_win_alt")
        #expect(level.pit.fx.trackID(for: "lose") == "sfx_pit_lose_alt")
        #expect(level.gate.fx.trackID(for: "opened") == "sfx_gate_opened")
        if case .soundOutWord(let soundOutWord) = level.gate.minigames.first {
            #expect(soundOutWord.fx.trackID(for: "win") == "sfx_gate_win_alt")
        }
        if case .graphemeMatch(let graphemeMatch) = level.gate.minigames.last {
            #expect(graphemeMatch.fx.trackID(for: "correct") == "sfx_wall_correct_alt")
        }
    }

    @Test func decodesPitWordIDsFromCatalog() throws {
        let yaml = """
        name: Level 1
        order: 1
        world:
          width_tiles: 20
          height_tiles: 20
          room_count: 4
          room:
            min_size_tiles: 4
            max_size_tiles: 8
            pit_probability: 0
        pit:
          minigames:
            - type: sound-out-word-pit
        """
        let level = try LevelConfig.decode(
            from: yaml,
            vocabularyCatalog: Self.vocabCatalog(
                words: ["sat", "can"],
                graphemes: ["s", "a", "t", "c", "n"]
            )
        )
        let soundOut = try pitSoundOutWord(level)
        #expect(Set(soundOut.words.map(\.word)).isSuperset(of: ["can", "sat"]))
    }

    
    @Test func rejectsEmptyPitWords() {
        let config = PitSoundOutWordConfig(
            words: [],
            graphemes: GraphemeCatalog.fallback.graphemes
        )
        #expect(throws: WorldSeedError.invalidPitSoundOutWordWords) {
            try config.validate()
        }
    }


    @Test func rejectsUnknownPitWordID() {
        let yaml = """
        name: Level 1
        order: 1
        world:
          width_tiles: 20
          height_tiles: 20
          room_count: 4
          room:
            min_size_tiles: 4
            max_size_tiles: 8
            pit_probability: 0
        pit:
          minigames:
            - type: sound-out-word-pit
        """
        #expect(throws: WorldSeedError.invalidGateWords) {
            try LevelConfig.decode(
                from: yaml,
                vocabularyCatalog: Self.vocabCatalog(
                    words: ["not_a_real_word"],
                    graphemes: ["a"]
                )
            )
        }
    }

    @Test func decodesGateGraphemeMatchConfigWithDefaultsWhenOmitted() throws {
        let level = try LevelConfig.decode(from: """
        name: Level 1
        world:
          width_tiles: 20
          height_tiles: 20
          room_count: 4
          room:
            min_size_tiles: 4
            max_size_tiles: 8
            pit_probability: 0
            gate_probability: 0
        """)
        #expect(level.gate.minigames.map(\.kind) == GateConfig.fallback.minigames.map(\.kind))
    }

    @Test func decodesGateGraphemeMatchConfigFromYAML() throws {
        let yaml = """
        name: Level 1
        order: 1
        world:
          width_tiles: 20
          height_tiles: 20
          room_count: 4
          room:
            min_size_tiles: 4
            max_size_tiles: 8
            pit_probability: 0
            gate_probability: 0
        gate:
          fx: { opened: sfx_gate_opened }
          minigames:
            - type: grapheme-sound-gate
              min_grapheme_count: 2
              max_grapheme_count: 3
        """
        let level = try LevelConfig.decode(
            from: yaml,
            vocabularyCatalog: Self.vocabCatalog(
                words: ["at"],
                graphemes: ["b", "a"]
            )
        )
        guard case .graphemeMatch(let lm) = level.gate.minigames.first else {
            Issue.record("expected letter_match minigame")
            return
        }
        #expect(lm.graphemeCountMin == 2)
        #expect(lm.graphemeCountMax == 3)
        #expect(Set(lm.graphemes.map(\.grapheme)).isSuperset(of: ["a", "b"]))
    }

    @Test func inheritsGateGraphemeMatchConfigFromBase() throws {
        let base = Self.baseLevelYAMLWithoutPuzzles + """

        gate:
          fx: { opened: sfx_gate_opened }
          minigames:
            - type: grapheme-sound-gate
              min_grapheme_count: 1
              max_grapheme_count: 2
        """
        let child = """
        inherits: base_level
        name: Level 1
        """
        let level = try LevelConfig.decode(
            from: child,
            parents: ["base_level": base],
            vocabularyCatalog: Self.vocabCatalog(
                words: ["at"],
                graphemes: ["a", "c"]
            )
        )
        guard case .graphemeMatch(let lm) = level.gate.minigames.first else {
            Issue.record("expected letter_match minigame")
            return
        }
        #expect(lm.graphemeCountMin == 1)
        #expect(lm.graphemeCountMax == 2)
        #expect(Set(lm.graphemes.map(\.grapheme)).isSuperset(of: ["a", "c"]))
    }

    @Test func childCanOverrideInheritedGateGraphemeMatchLetterIDs() throws {
        let base = Self.baseLevelYAMLWithoutPuzzles + """

        gate:
          fx: { opened: sfx_gate_opened }
          minigames:
            - type: grapheme-sound-gate
        """
        let child = """
        inherits: base_level
        name: Level 1
        order: 1
        vocab:
          graphemes: [b]
          words: [at]
        gate:
          minigames:
            - type: grapheme-sound-gate
        """
        let level = try LevelConfig.decode(
            from: child,
            parents: ["base_level": base],
            vocabularyCatalog: Self.vocabCatalog(
                words: ["at"],
                graphemes: ["b"]
            )
        )
        guard case .graphemeMatch(let lm) = level.gate.minigames.first else {
            Issue.record("expected letter_match minigame")
            return
        }
        #expect(Set(lm.graphemes.map(\.grapheme)).isSuperset(of: ["b"]))
    }

    @Test func rejectsInvalidGateGraphemeMatchLetterCountRange() {
        let yaml = """
        name: Level 1
        world:
          width_tiles: 20
          height_tiles: 20
          room_count: 4
          room:
            min_size_tiles: 4
            max_size_tiles: 8
            pit_probability: 0
            gate_probability: 0
        gate:
          fx: { opened: sfx_gate_opened }
          minigames:
            - type: grapheme-sound-gate
              min_grapheme_count: 4
              max_grapheme_count: 2
              graphemes: [a]
        """
        #expect(throws: WorldSeedError.invalidGateGraphemeMatchCountRange(min: 4, max: 2)) {
            try LevelConfig.decode(from: yaml)
        }
    }

    
    @Test func rejectsEmptyGateGraphemeMatchLetters() {
        let config = GateGraphemeMatchConfig(graphemes: [])
        #expect(throws: WorldSeedError.invalidGateGraphemeMatchGraphemes) {
            try config.validate()
        }
    }


    @Test func rejectsUnknownGateGraphemeMatchLetterID() {
        let yaml = """
        name: Level 1
        order: 1
        world:
          width_tiles: 20
          height_tiles: 20
          room_count: 4
          room:
            min_size_tiles: 4
            max_size_tiles: 8
            pit_probability: 0
            gate_probability: 0
        gate:
          fx: { opened: sfx_gate_opened }
          minigames:
            - type: grapheme-sound-gate
        """
        #expect(throws: WorldSeedError.invalidGateGraphemeMatchGraphemes) {
            try LevelConfig.decode(
                from: yaml,
                vocabularyCatalog: Self.vocabCatalog(words: ["at"], graphemes: ["qq"])
            )
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
        #expect(wp.words.map(\.word) == ["an", "at", "in", "it", "nap", "pan", "pat", "pin", "sat", "sip", "sit", "tap"])
        #expect(tython.artifact == "leaf.fill")
    }

    @Test func decodesGateWordPlugMinigame() throws {
        let yaml = """
        name: Level 1
        order: 1
        world:
          width_tiles: 20
          height_tiles: 20
          room_count: 4
          room:
            min_size_tiles: 4
            max_size_tiles: 8
            pit_probability: 0
            gate_probability: 0
        gate:
          fx: { opened: sfx_gate_opened }
          minigames:
            - type: starting-sound-gate
              min_word_count: 2
              max_word_count: 2
        """
        let level = try LevelConfig.decode(
            from: yaml,
            vocabularyCatalog: Self.vocabCatalog(
                words: ["cat", "dog"],
                graphemes: ["c", "a", "t", "d", "o", "g"]
            )
        )
        guard case .wordPlug(let wp) = level.gate.minigames.first else {
            Issue.record("expected word_plug minigame")
            return
        }
        #expect(wp.wordCountMin == 2)
        #expect(wp.wordCountMax == 2)
        #expect(Set(wp.words.map(\.word)).isSuperset(of: ["cat", "dog"]))
        #expect(!wp.graphemes.isEmpty)
    }

    @Test func decodesGateEndingSoundMinigame() throws {
        let yaml = """
        name: Level 1
        order: 1
        world:
          width_tiles: 20
          height_tiles: 20
          room_count: 4
          room:
            min_size_tiles: 4
            max_size_tiles: 8
            pit_probability: 0
            gate_probability: 0
        gate:
          fx: { opened: sfx_gate_opened }
          minigames:
            - type: ending-sound-gate
              min_word_count: 2
              max_word_count: 2
        """
        let level = try LevelConfig.decode(
            from: yaml,
            vocabularyCatalog: Self.vocabCatalog(
                words: ["dog", "hat"],
                graphemes: ["d", "o", "g", "h", "a", "t"]
            )
        )
        guard case .wordPlug(let wp) = level.gate.minigames.first else {
            Issue.record("expected ending-sound gate minigame")
            return
        }
        #expect(level.gate.minigames.map(\.kind) == [.endingSoundPlug])
        #expect(wp.letterPosition == .ending)
        #expect(Set(wp.words.map(\.word)).isSuperset(of: ["dog", "hat"]))
        #expect(!wp.graphemes.isEmpty)
    }

    @Test func rejectsGateEndingSoundWordWithoutGraphemeAudio() {
        // The shipped catalog covers every letter, so pair a word with a trimmed grapheme
        // list to reach the missing-audio guard.
        let config = GateWordPlugConfig(
            wordCountMin: 1,
            wordCountMax: 1,
            letterPosition: .ending,
            words: [GateWord.fallbackEntry(word: "cat")],
            graphemes: [
                GateGrapheme(grapheme: "c", pronunciation: "sfx_letter_c", name: "sfx_letter_c_name"),
                GateGrapheme(grapheme: "a", pronunciation: "sfx_letter_a", name: "sfx_letter_a_name"),
            ]
        )
        #expect(throws: WorldSeedError.invalidGateWordPlugGraphemes) {
            try config.validate()
        }
    }

    @Test func allowsBothGateSoundMinigamesTogether() throws {
        let yaml = """
        name: Level 1
        world:
          width_tiles: 20
          height_tiles: 20
          room_count: 4
          room:
            min_size_tiles: 4
            max_size_tiles: 8
            pit_probability: 0
            gate_probability: 0
        gate:
          fx: { opened: sfx_gate_opened }
          minigames:
            - type: starting-sound-gate
              words: [cat, dog]
            - type: ending-sound-gate
              words: [dog, web]
        """
        let level = try LevelConfig.decode(from: yaml)
        #expect(level.gate.minigames.map(\.kind) == [.wordPlug, .endingSoundPlug])
    }

    @Test func acceptsNonMultipleOfThreeGateWordPlugWordCount() throws {
        let yaml = """
        name: Level 1
        world:
          width_tiles: 20
          height_tiles: 20
          room_count: 4
          room:
            min_size_tiles: 4
            max_size_tiles: 8
            pit_probability: 0
            gate_probability: 0
        gate:
          fx: { opened: sfx_gate_opened }
          minigames:
            - type: starting-sound-gate
              min_word_count: 2
              max_word_count: 4
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
        world:
          width_tiles: 20
          height_tiles: 20
          room_count: 4
          room:
            min_size_tiles: 4
            max_size_tiles: 8
            pit_probability: 0
            gate_probability: 0
        gate:
          fx: { opened: sfx_gate_opened }
          minigames:
            - type: starting-sound-gate
              min_word_count: 3
              max_word_count: 12
              words: [cat, dog]
        """
        #expect(throws: WorldSeedError.invalidGateWordPlugWordCountRange(min: 3, max: 12)) {
            try LevelConfig.decode(from: yaml)
        }
    }

    
    @Test func rejectsUnknownGateWordPlugWordID() {
        let yaml = """
        name: Level 1
        order: 1
        world:
          width_tiles: 20
          height_tiles: 20
          room_count: 4
          room:
            min_size_tiles: 4
            max_size_tiles: 8
            pit_probability: 0
            gate_probability: 0
        gate:
          fx: { opened: sfx_gate_opened }
          minigames:
            - type: starting-sound-gate
              min_word_count: 1
              max_word_count: 1
        """
        #expect(throws: WorldSeedError.invalidGateWords) {
            try LevelConfig.decode(
                from: yaml,
                vocabularyCatalog: Self.vocabCatalog(
                    words: ["not_a_real_word"],
                    graphemes: ["a"]
                )
            )
        }
    }


    // MARK: - combat:

    /// Minimal level body the combat tests append a `combat:` block to.
    private static let combatLevelPrefix = """
    name: Level 1
    world:
      width_tiles: 20
      height_tiles: 20
      room_count: 4
      room:
        min_size_tiles: 4
        max_size_tiles: 8
        pit_probability: 0
        gate_probability: 0

    """

    @Test func defaultsToSlashOnlyWhenCombatBlockOmitted() throws {
        let level = try LevelConfig.decode(from: Self.combatLevelPrefix)
        #expect(level.combat == CombatConfig.fallback)
        #expect(level.combat.minigames.map(\.kind) == [.slash])
    }

    
    @Test func decodesCombatMinigamesFromYAML() throws {
        let level = try LevelConfig.decode(
            from: Self.combatLevelPrefix + """
            combat:
              minigames:
                - type: grapheme-sound-combat
                  weight: 0.0
                - type: ending-sound-combat
                  weight: 1.0
                  monster_hit_points: 4
                  orb_travel_seconds: 2.5
                  ring_count: 3
            """,
            vocabularyCatalog: Self.vocabCatalog(
                words: ["sat", "tap", "pan"],
                graphemes: ["s", "a", "t", "p", "n"]
            )
        )

        #expect(level.combat.minigames.map(\.kind) == [.slash, .endingSoundDeflect])
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
        #expect(deflect.letterPosition == .ending)
        #expect(deflect.ringCount == 3)
        // Ending rings are pool graphemes with ≥1 imaged match (t/p/n here).
        #expect(deflect.graphemes.map(\.grapheme) == ["t", "p", "n"])
    }


    @Test func deflectFallsBackToDefaultHPTravelAndLetters() throws {
        let level = try LevelConfig.decode(from: Self.combatLevelPrefix + """
        combat:
          minigames:
            - type: ending-sound-combat
        """)
        guard case .deflect(let deflect) = level.combat.minigames.first else {
            Issue.record("expected a deflect entry")
            return
        }
        #expect(deflect.weight == 1)
        #expect(deflect.monsterHP == CombatDeflectConfig.defaultMonsterHP)
        #expect(deflect.orbTravelSeconds == CombatDeflectConfig.defaultOrbTravelSeconds)
        #expect(deflect.ringCount == CombatDeflectConfig.defaultRingCount)
        // Ending-sound on the Level-1 pool only has t/p/n candidates.
        #expect(deflect.graphemes.map(\.grapheme) == ["t", "p", "n"])
    }

    @Test func decodesStartingSoundCombat() throws {
        let level = try LevelConfig.decode(from: Self.combatLevelPrefix + """
        combat:
          minigames:
            - type: starting-sound-combat
        """)
        #expect(level.combat.minigames.map(\.kind) == [.startingSoundDeflect])
        guard case .deflect(let deflect) = level.combat.minigames.first else {
            Issue.record("expected a starting-sound deflect entry")
            return
        }
        #expect(deflect.letterPosition == .starting)
    }

    @Test func decodesEndingSoundCombatAsAnEndPosition() throws {
        let level = try LevelConfig.decode(from: Self.combatLevelPrefix + """
        combat:
          minigames:
            - type: ending-sound-combat
        """)
        #expect(level.combat.minigames.map(\.kind) == [.endingSoundDeflect])
        guard case .deflect(let deflect) = level.combat.minigames.first else {
            Issue.record("expected an ending-sound deflect entry")
            return
        }
        #expect(deflect.letterPosition == .ending)
    }

    @Test func acceptsBothSoundCombatVariantsTogether() throws {
        let level = try LevelConfig.decode(from: Self.combatLevelPrefix + """
        combat:
          minigames:
            - type: starting-sound-combat
              graphemes: [a, b, c, d]
            - type: ending-sound-combat
              graphemes: [t, d, n, r]
        """)
        #expect(level.combat.minigames.map(\.kind) == [
            .startingSoundDeflect, .endingSoundDeflect,
        ])
    }

    
    @Test func inheritsCombatBlockFromBase() throws {
        let base = Self.combatLevelPrefix + """
        combat:
          minigames:
            - type: ending-sound-combat
              weight: 1.0
              monster_hit_points: 7
              ring_count: 3
        """
        let level = try LevelConfig.decode(
            from: "inherits: base_level\nname: Level 2\norder: 1",
            parents: ["base_level": base],
            vocabularyCatalog: Self.vocabCatalog(
                words: ["sat", "tap", "pan"],
                graphemes: ["s", "a", "t", "p", "n"]
            )
        )
        guard case .deflect(let deflect) = level.combat.minigames.first else {
            Issue.record("expected an inherited deflect entry")
            return
        }
        #expect(deflect.monsterHP == 7)
        #expect(deflect.ringCount == 3)
        #expect(deflect.graphemes.map(\.grapheme) == ["t", "p", "n"])
    }


    @Test func pickMinigameNeverChoosesAZeroWeightEntry() throws {
        let config = CombatConfig(minigames: [
            .slash(CombatSlashConfig(weight: 0)),
            .deflect(CombatDeflectConfig(weight: 1)),
        ])
        var rng = CombatSeededGenerator(seed: 5)
        for _ in 0..<200 {
            #expect(try config.pickMinigame(using: &rng).kind == .startingSoundDeflect)
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
        #expect(seen == [.slash, .startingSoundDeflect])
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
                - type: ending-sound-combat
                  weight: -1.0
            """)
        }
    }

    @Test func rejectsDuplicateCombatMinigameTypes() {
        #expect {
            try LevelConfig.decode(from: Self.combatLevelPrefix + """
            combat:
              minigames:
                - type: ending-sound-combat
                - type: ending-sound-combat
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
                - type: ending-sound-combat
                  monster_hit_points: 0
            """)
        }
    }

    @Test func rejectsNonPositiveCombatOrbTravelSeconds() {
        #expect(throws: WorldSeedError.invalidCombatOrbTravelSeconds(0)) {
            try LevelConfig.decode(from: Self.combatLevelPrefix + """
            combat:
              minigames:
                - type: ending-sound-combat
                  orb_travel_seconds: 0
            """)
        }
    }

    
    @Test func rejectsUnknownCombatDeflectLetterID() {
        #expect(throws: WorldSeedError.invalidGateGraphemeMatchGraphemes) {
            try LevelConfig.decode(
                from: Self.combatLevelPrefix + """
                order: 1
                combat:
                  minigames:
                    - type: ending-sound-combat
                      ring_count: 3
                """,
                vocabularyCatalog: Self.vocabCatalog(
                    words: ["cat"],
                    graphemes: ["a", "b", "not_a_letter"]
                )
            )
        }
    }


    
    
    @Test func clampsCombatDeflectRingCountToCandidateBounds() throws {
        var tooFew = CombatDeflectConfig(letterPosition: .starting, ringCount: 1)
        try tooFew.resolve(from: LevelVocabularyPool.fallback)
        #expect(tooFew.graphemes.count >= CombatDeflectConfig.minRingCount)
        try tooFew.validate()

        var tooMany = CombatDeflectConfig(letterPosition: .starting, ringCount: 7)
        try tooMany.resolve(from: LevelVocabularyPool.fallback)
        #expect(tooMany.graphemes.count <= CombatDeflectConfig.maxRingCount)
        try tooMany.validate()
    }



    
    @Test func acceptsCombatDeflectLetterCountsFromTwoToSix() throws {
        let level = try LevelConfig.decode(
            from: Self.combatLevelPrefix + """
            order: 1
            combat:
              minigames:
                - type: starting-sound-combat
                  ring_count: 4
            """,
            vocabularyCatalog: Self.vocabCatalog(
                words: ["at", "bed", "cat", "dad"],
                graphemes: ["a", "b", "c", "d", "t", "e"]
            )
        )
        guard case .deflect(let deflect) = level.combat.minigames.first else {
            Issue.record("expected a deflect entry")
            return
        }
        #expect(deflect.graphemes.count == 4)
    }


    
    
    @Test func rejectsDuplicateCombatDeflectLetters() {
        // Pool too small for ring_count fails validation after resolve.
        var config = CombatDeflectConfig(ringCount: 3, graphemes: [])
        var pool = LevelVocabularyPool(tiers: [
            .init(
                order: 1,
                weight: 1,
                words: [],
                graphemes: [
                    GateGrapheme(grapheme: "a", pronunciation: "p", name: "n"),
                ]
            ),
        ])
        #expect(throws: WorldSeedError.invalidCombatDeflectGraphemes) {
            try config.resolve(from: pool)
            try config.validate()
        }
    }



    
    @Test func bundleDefaultsProvideDeflectCombatConfig() throws {
        let tython = try LevelConfig.loadFromBundle(
            named: "1-tython",
            subdirectory: LevelCatalog.subdirectory
        )
        guard case .deflect(let deflect) = tython.combat.minigames[1] else {
            Issue.record("expected starting-sound deflect")
            return
        }
        #expect(deflect.graphemes.map(\.grapheme) == ["s", "a", "t", "p"])
        #expect(deflect.ringCount == 4)
    }


    @Test func decodesSlashLetterSoundRepeatSeconds() throws {
        let level = try LevelConfig.decode(from: Self.combatLevelPrefix + """
        combat:
          minigames:
            - type: grapheme-sound-combat
              grapheme_sound_repeat_seconds: 5
        """)
        guard case .slash(let slash) = level.combat.minigames.first else {
            Issue.record("expected slash entry")
            return
        }
        #expect(slash.graphemeSoundRepeatSeconds == 5)
    }

    @Test func gateConfigLooksUpMinigameByKind() {
        let config = GateConfig.fallback
        #expect(config.weightedMinigameKinds.map(\.kind) == [.soundOutWord, .graphemeMatch])
        guard case .graphemeMatch = config.minigame(for: .graphemeMatch) else {
            Issue.record("expected grapheme_match config")
            return
        }
        guard case .soundOutWord = config.minigame(for: .soundOutWord) else {
            Issue.record("expected sound_out_word config")
            return
        }
        let duplicated = GateConfig(
            fx: config.fx,
            minigames: [
                .soundOutWord(.fallback),
                .graphemeMatch(.fallback),
                .soundOutWord(.fallback),
            ]
        )
        #expect(throws: WorldSeedError.duplicateGateMinigameKind(.soundOutWord)) {
            try duplicated.validate()
        }
    }

    @Test func decodesEnemiesSpawnBlock() throws {
        let yaml = """
        name: Level
        world:
          width_tiles: 10
          height_tiles: 10
          room_count: 2
          room:
            min_size_tiles: 4
            max_size_tiles: 12
            pit_probability: 0.0
          enemies:
            types: [spider, ice_monster]
            spawn_probability_per_room: 0.8
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
        world:
          width_tiles: 10
          height_tiles: 10
          room_count: 2
          room:
            min_size_tiles: 4
            max_size_tiles: 12
            pit_probability: 0.0
          enemies:
            type: spider
            spawn_probability_per_room: 1.5
        """

        #expect(throws: WorldSeedError.invalidEnemySpawnChance(1.5)) {
            try LevelConfig.decode(from: yaml)
        }
    }

    @Test func decodesPickupsSpawnBlock() throws {
        let yaml = """
        name: Level
        world:
          width_tiles: 10
          height_tiles: 10
          room_count: 2
          room:
            min_size_tiles: 4
            max_size_tiles: 12
            pit_probability: 0.0
          pickups:
            health:
              spawn_probability_per_room: 0.8
            energy:
              spawn_probability_per_room: 0.5
        """

        let level = try LevelConfig.decode(from: yaml)
        #expect(level.pickups?.health?.spawnChancePerRoom == 0.8)
        #expect(level.pickups?.energy?.spawnChancePerRoom == 0.5)
        try level.validate()
    }

    @Test func rejectsInvalidPickupSpawnChance() throws {
        let yaml = """
        name: Level
        world:
          width_tiles: 10
          height_tiles: 10
          room_count: 2
          room:
            min_size_tiles: 4
            max_size_tiles: 12
            pit_probability: 0.0
          pickups:
            health:
              spawn_probability_per_room: -0.1
        """

        #expect(throws: WorldSeedError.invalidPickupSpawnChance(kind: .health, chance: -0.1)) {
            try LevelConfig.decode(from: yaml)
        }
    }

    @Test func rejectsInvalidPitSize() throws {
        let yaml = """
        name: Level
        world:
          width_tiles: 10
          height_tiles: 10
          room_count: 2
          room:
            min_size_tiles: 4
            max_size_tiles: 12
            pit_probability: 0.2
            pit_mean_size_tiles: 6
            pit_max_size_tiles: 5
        """

        #expect(throws: WorldSeedError.invalidRoomPitSize(mean: 6, max: 5)) {
            try LevelConfig.decode(from: yaml)
        }
    }

    @Test func rejectsInvalidGateProbability() throws {
        let yaml = """
        name: Level
        world:
          width_tiles: 10
          height_tiles: 10
          room_count: 2
          room:
            min_size_tiles: 4
            max_size_tiles: 12
            pit_probability: 0.0
            gate_probability: 1.5
        """

        #expect(throws: WorldSeedError.invalidGateProbability(1.5)) {
            try LevelConfig.decode(from: yaml)
        }
    }

    // MARK: - pit.minigames:

    /// Minimal level body the pit minigame tests append a `pit:` block to.
    private static let pitLevelPrefix = """
    name: Level 1
    world:
      width_tiles: 20
      height_tiles: 20
      room_count: 4
      room:
        min_size_tiles: 4
        max_size_tiles: 8
        pit_probability: 0
        gate_probability: 0

    """

    @Test func defaultsToSoundOutWordOnlyWhenPitBlockOmitted() throws {
        let level = try LevelConfig.decode(from: Self.pitLevelPrefix)
        #expect(level.pit.fx.trackID(for: "jump") == "pit-jump")
        #expect(level.pit.fx.trackID(for: "lose") == nil)
        #expect(level.pit.minigames.map(\.kind) == [.soundOutWord])
        let soundOut = try pitSoundOutWord(level)
        #expect(soundOut.weight == 1)
        #expect(!soundOut.words.isEmpty)
    }

    
    @Test func decodesPitMinigamesFromYAML() throws {
        let level = try LevelConfig.decode(
            from: Self.pitLevelPrefix + """
            pit:
              fx: { jump: pit-jump }
              minigames:
                - type: sound-out-word-pit
                  weight: 0.0
                  min_choice_count: 3
                  max_choice_count: 3
                - type: ending-sound-pit
                  weight: 1.0
                  min_word_count: 2
                  max_word_count: 4
            """,
            vocabularyCatalog: Self.vocabCatalog(
                words: ["cat", "dog", "sun", "sat", "hat", "bed"],
                graphemes: ["c", "a", "t", "d", "o", "g", "s", "u", "n", "h", "b", "e"]
            )
        )
        #expect(level.pit.fx.trackID(for: "jump") == "pit-jump")
        #expect(level.pit.minigames.map(\.kind) == [.soundOutWord, .bridge])
        if case .soundOutWord(let soundOut) = level.pit.minigames[0] {
            #expect(soundOut.weight == 0)
            #expect(soundOut.choiceCountMin == 3)
            #expect(soundOut.choiceCountMax == 3)
            #expect(Set(soundOut.words.map(\.word)).isSuperset(of: ["bed", "cat", "dog", "hat", "sat", "sun"]))
        } else {
            Issue.record("expected sound-out-word entry")
        }
        if case .bridge(let bridge) = level.pit.minigames[1] {
            #expect(bridge.weight == 1)
            #expect(bridge.minWords == 2)
            #expect(bridge.maxWords == 4)
            #expect(Set(bridge.words.map(\.word)).isSuperset(of: ["bed", "cat", "dog", "hat", "sat", "sun"]))
            #expect(bridge.words.allSatisfy { ($0.image?.isEmpty == false) })
        } else {
            Issue.record("expected bridge entry")
        }
    }


    @Test func bridgeFallsBackToDefaultMinMaxAndWords() throws {
        let level = try LevelConfig.decode(from: Self.pitLevelPrefix + """
        pit:
          minigames:
            - type: ending-sound-pit
              weight: 1
        """)
        guard case .bridge(let bridge) = level.pit.minigames.first else {
            Issue.record("expected bridge entry")
            return
        }
        #expect(bridge.minWords == PitBridgeConfig.defaultMinWords)
        #expect(bridge.maxWords == PitBridgeConfig.defaultMaxWords)
        #expect(bridge.letterPosition == .ending)
        #expect(bridge.words.count >= bridge.maxWords)
        #expect(bridge.words.allSatisfy { ($0.image?.isEmpty == false) })
    }

    
    @Test func decodesStartingSoundPitFromYAML() throws {
        let level = try LevelConfig.decode(
            from: Self.pitLevelPrefix + """
            pit:
              minigames:
                - type: starting-sound-pit
                  weight: 1.0
                  min_word_count: 3
                  max_word_count: 5
            """,
            vocabularyCatalog: Self.vocabCatalog(
                words: ["cat", "dog", "sun", "sat", "hat", "bed"],
                graphemes: ["c", "a", "t", "d", "o", "g", "s", "u", "n", "h", "b", "e"]
            )
        )
        #expect(level.pit.minigames.map(\.kind) == [.startingSoundBridge])
        guard case .bridge(let bridge) = level.pit.minigames.first else {
            Issue.record("expected starting-sound bridge entry")
            return
        }
        #expect(bridge.letterPosition == .starting)
        #expect(bridge.weight == 1)
        #expect(bridge.minWords == 3)
        #expect(bridge.maxWords == 5)
        #expect(Set(bridge.words.map(\.word)).isSuperset(of: ["bed", "cat", "dog", "hat", "sat", "sun"]))
    }


    
    @Test func inheritsPitBlockFromBase() throws {
        let base = Self.baseLevelYAMLWithoutPuzzles + """

        pit:
          fx: { jump: pit-jump }
          minigames:
            - type: ending-sound-pit
              weight: 1
              min_word_count: 2
              max_word_count: 3
        """
        let child = """
        inherits: base_level
        name: Child
        """
        let level = try LevelConfig.decode(
            from: child,
            parents: ["base_level": base],
            vocabularyCatalog: Self.vocabCatalog(
                words: ["cat", "dog", "sun", "sat"],
                graphemes: ["c", "a", "t", "d", "o", "g", "s", "u", "n"]
            )
        )
        guard case .bridge(let bridge) = level.pit.minigames.first else {
            Issue.record("expected bridge entry")
            return
        }
        #expect(bridge.minWords == 2)
        #expect(bridge.maxWords == 3)
        #expect(bridge.words.count >= bridge.maxWords)
        #expect(Set(bridge.words.map(\.word)).isSuperset(of: ["cat", "dog", "sat", "sun"]))
    }


    @Test func childCanOverrideInheritedPitMinigames() throws {
        let base = Self.baseLevelYAMLWithoutPuzzles + """

        pit:
          minigames:
            - type: sound-out-word-pit
              words: [cat]
        """
        let child = """
        inherits: base_level
        name: Child
        pit:
          minigames:
            - type: ending-sound-pit
              words: [cat, dog, sun, sat, hat, bed]
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
                .soundOutWord(PitSoundOutWordConfig(weight: 0, words: PitSoundOutWordConfig.fallback.words, graphemes: PitSoundOutWordConfig.fallback.graphemes)),
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
                .soundOutWord(PitSoundOutWordConfig(weight: 1, words: PitSoundOutWordConfig.fallback.words, graphemes: PitSoundOutWordConfig.fallback.graphemes)),
                .bridge(PitBridgeConfig(weight: 1)),
                .bridge(PitBridgeConfig(weight: 1, letterPosition: .starting)),
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
                .soundOutWord(PitSoundOutWordConfig(weight: 0, words: PitSoundOutWordConfig.fallback.words, graphemes: PitSoundOutWordConfig.fallback.graphemes)),
                .bridge(PitBridgeConfig(weight: 0)),
            ]
        )
        var rng = PitSeededGenerator(seed: 3)
        #expect(try config.pickMinigame(using: &rng).kind == .soundOutWord)
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
                - type: ending-sound-pit
                - type: ending-sound-pit
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

    @Test func rejectsDuplicateStartingSoundPitMinigameTypes() {
        #expect {
            try LevelConfig.decode(from: Self.pitLevelPrefix + """
            pit:
              minigames:
                - type: starting-sound-pit
                - type: starting-sound-pit
                  weight: 2
            """)
        } throws: { error in
            guard let error = error as? WorldSeedError,
                  case .decodeFailed(let message) = error else {
                return false
            }
            return message.contains("duplicate type 'starting-sound-pit'")
        }
    }

    @Test func rejectsNegativePitMinigameWeight() {
        #expect(throws: WorldSeedError.invalidPitMinigameWeight(-1)) {
            try LevelConfig.decode(from: Self.pitLevelPrefix + """
            pit:
              minigames:
                - type: ending-sound-pit
                  weight: -1
            """)
        }
    }

    @Test func rejectsNegativeGateMinigameWeight() {
        #expect(throws: WorldSeedError.invalidGateMinigameWeight(-1)) {
            try LevelConfig.decode(from: Self.pitLevelPrefix + """
            gate:
              fx: { opened: sfx_gate_opened }
              minigames:
                - type: sound-out-word-gate
                  weight: -1
                  words: [cat]
            """)
        }
    }

    @Test func rejectsDuplicateGateMinigameKinds() {
        #expect(throws: WorldSeedError.duplicateGateMinigameKind(.soundOutWord)) {
            try LevelConfig.decode(from: Self.pitLevelPrefix + """
            gate:
              fx: { opened: sfx_gate_opened }
              minigames:
                - type: sound-out-word-gate
                  words: [cat]
                - type: sound-out-word-gate
                  words: [dog]
            """)
        }
    }

    @Test func rejectsInvalidPitBridgeWordRange() {
        #expect(throws: WorldSeedError.invalidPitBridgeWordRange(min: 0, max: 4)) {
            try LevelConfig.decode(from: Self.pitLevelPrefix + """
            pit:
              minigames:
                - type: ending-sound-pit
                  min_word_count: 0
                  max_word_count: 4
            """)
        }
        #expect(throws: WorldSeedError.invalidPitBridgeWordRange(min: 5, max: 2)) {
            try LevelConfig.decode(from: Self.pitLevelPrefix + """
            pit:
              minigames:
                - type: ending-sound-pit
                  min_word_count: 5
                  max_word_count: 2
                  words: [cat, dog, sun, sat, hat, bed]
            """)
        }
    }

    
    @Test func rejectsPitBridgePoolSmallerThanMaxWords() {
        #expect(throws: WorldSeedError.invalidPitBridgeWords) {
            try LevelConfig.decode(
                from: Self.pitLevelPrefix + """
                pit:
                  minigames:
                    - type: ending-sound-pit
                      min_word_count: 2
                      max_word_count: 4
                """,
                vocabularyCatalog: Self.vocabCatalog(
                    words: ["cat"],
                    graphemes: ["c", "a", "t", "d", "o", "g", "s", "u", "n"],
                    supportOmittedPit: false
                )
            )
        }
    }

    @Test func rejectsPitBridgeDuplicateOrUnknownWords() {
        #expect(throws: WorldSeedError.invalidGateWords) {
            try LevelConfig.decode(
                from: Self.pitLevelPrefix + """
                pit:
                  minigames:
                    - type: ending-sound-pit
                      min_word_count: 1
                      max_word_count: 1
                """,
                vocabularyCatalog: Self.vocabCatalog(
                    words: ["not_a_real_word"],
                    graphemes: ["a"]
                )
            )
        }
    }


    
    @Test func rejectsPitBridgeWordsWithoutImages() throws {
        // Curriculum words are all imaged; inject an audio-only entry and point vocab at it.
        let catalog = WordCatalog(words: WordCatalog.fallback.words + [
            GateWord.fallbackEntry(word: "silent"),
        ])
        #expect(throws: WorldSeedError.invalidPitBridgeWords) {
            try LevelConfig.decode(
                from: Self.pitLevelPrefix + """
                pit:
                  minigames:
                    - type: ending-sound-pit
                      min_word_count: 1
                      max_word_count: 1
                """,
                wordCatalog: catalog,
                vocabularyCatalog: Self.vocabCatalog(
                    words: ["silent"],
                    graphemes: ["s", "i", "l", "e", "n", "t", "a", "b", "c", "d"],
                    supportOmittedPit: false
                )
            )
        }
    }


    
    @Test func bundleDefaultsProvideBridgePitConfig() throws {
        let tython = try LevelConfig.loadFromBundle(
            named: "1-tython",
            subdirectory: LevelCatalog.subdirectory
        )
        #expect(tython.pit.minigames.map(\.kind) == [.soundOutWord, .bridge, .startingSoundBridge])
        #expect(tython.pit.minigames.map(\.weight) == [1, 1, 1])
        if case .bridge(let bridge) = tython.pit.minigames[1] {
            #expect(bridge.letterPosition == .ending)
            #expect(bridge.words.map(\.word) == ["an", "at", "in", "it", "nap", "pan", "pat", "pin", "sat", "sip", "sit", "tap"])
        } else {
            Issue.record("expected bridge entry")
        }
        if case .bridge(let starting) = tython.pit.minigames[2] {
            #expect(starting.letterPosition == .starting)
            #expect(starting.words.map(\.word) == ["an", "at", "in", "it", "nap", "pan", "pat", "pin", "sat", "sip", "sit", "tap"])
        } else {
            Issue.record("expected starting-sound bridge entry")
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

    // MARK: - Override / inheritance guarantees

    @Test func everyDefaultsKeyIsOverridableByAChildLevel() throws {
        let defaultsData = try ConfigStore.data(at: .levelDefaults)
        let defaultsTree = try ConfigStore.rawTree(
            from: defaultsData,
            parentDataNamed: nil,
            fileLabel: "_defaults"
        )
        let leaves = Self.collectLeaves(from: defaultsTree)
        #expect(!leaves.isEmpty)

        for leaf in leaves {
            let path = leaf.path
            if path == ["inherits"] { continue }
            if path == ["sprite"] { continue }
            if path == ["world", "floor", "set"] { continue }
            if path == ["letters", "set"] { continue }

            let sentinel = Self.sentinel(differingFrom: leaf.value)
            var childDict: [String: Any] = ["inherits": "_defaults", "name": "OverrideProbe"]
            Self.setValue(sentinel, at: path, in: &childDict)
            let childYAML = try Yams.dump(object: childDict)
            let childData = Data(childYAML.utf8)

            let merged = try ConfigStore.rawTree(
                from: childData,
                parentDataNamed: { _ in defaultsData },
                fileLabel: "test"
            )
            let actual = Self.value(at: path, in: merged)
            #expect(
                Self.yamlEqual(actual, sentinel),
                "override failed at \(path.joined(separator: ".")): got \(String(describing: actual))"
            )
        }
    }

    @Test func childCanOverrideWorldPickupsWithoutLosingSibling() throws {
        let defaultsData = try ConfigStore.data(at: .levelDefaults)
        let child = """
        inherits: _defaults
        name: PickupOverride
        world:
          pickups:
            health:
              spawn_probability_per_room: 0.25
        """
        let merged = try ConfigStore.rawTree(
            from: Data(child.utf8),
            parentDataNamed: { _ in defaultsData },
            fileLabel: "test"
        )
        let world = merged["world"] as? [String: Any]
        let pickups = world?["pickups"] as? [String: Any]
        let health = pickups?["health"] as? [String: Any]
        let energy = pickups?["energy"] as? [String: Any]
        #expect(health?["spawn_probability_per_room"] as? Double == 0.25)
        #expect(energy?["spawn_probability_per_room"] as? Double == 0.8)

        let level = try LevelConfig.decode(
            from: Data(child.utf8),
            parentDataNamed: { _ in defaultsData },
            fileLabel: "test",
            levelID: "1-tython"
        )
        #expect(level.pickups?.health?.spawnChancePerRoom == 0.25)
        #expect(level.pickups?.energy?.spawnChancePerRoom == 0.8)
    }

    @Test func realisticChildOverridesDecodeAndValidate() throws {
        let child = """
        inherits: _defaults
        name: Custom
        world:
          width_tiles: 24
          room:
            max_size_tiles: 8
            gate_probability: 0.5
          enemies:
            types: [spider]
            spawn_probability_per_room: 0.4
        combat:
          music: combat
          minigames:
            - type: grapheme-sound-combat
              weight: 0.0
              min_decoy_count: 2
              max_decoy_count: 4
              grapheme_case: lower
              grapheme_sound_repeat_seconds: 3
            - type: ending-sound-combat
              weight: 1.0
              monster_hit_points: 5
              orb_travel_seconds: 3.0
              graphemes: [a, b, c, d]
        """
        let level = try LevelConfig.loadFromBundle(
            named: "1-tython",
            subdirectory: LevelCatalog.subdirectory
        )
        // Decode the child against shipped defaults.
        let defaultsData = try ConfigStore.data(at: .levelDefaults)
        let decoded = try LevelConfig.decode(
            from: Data(child.utf8),
            parentDataNamed: { _ in defaultsData },
            fileLabel: "test",
            levelID: "1-tython"
        )
        #expect(decoded.name == "Custom")
        #expect(decoded.width == 24)
        #expect(decoded.room.maxRoomSize == 8)
        #expect(decoded.room.gateProbability == 0.5)
        #expect(decoded.enemies?.spawnChancePerRoom == 0.4)
        #expect(decoded.height == level.height)
        try decoded.validate()
    }

    // MARK: - Override helpers

    private struct Leaf {
        let path: [String]
        let value: Any
    }

    private static func collectLeaves(from tree: [String: Any], prefix: [String] = []) -> [Leaf] {
        var leaves: [Leaf] = []
        for key in tree.keys.sorted() {
            let path = prefix + [key]
            let value = tree[key] as Any
            if let dict = value as? [String: Any] {
                leaves.append(contentsOf: collectLeaves(from: dict, prefix: path))
            } else {
                leaves.append(Leaf(path: path, value: value))
            }
        }
        return leaves
    }

    private static func sentinel(differingFrom value: Any) -> Any {
        switch value {
        case let int as Int:
            return int + 1
        case let double as Double:
            return double + 1
        case let string as String:
            return string + "_x"
        case let bool as Bool:
            return !bool
        case let array as [Any]:
            var copy = array
            if copy.isEmpty {
                copy.append("x")
            } else {
                copy.removeLast()
            }
            return copy
        default:
            return "sentinel"
        }
    }

    private static func setValue(_ value: Any, at path: [String], in dict: inout [String: Any]) {
        guard let first = path.first else { return }
        if path.count == 1 {
            dict[first] = value
            return
        }
        var nested = dict[first] as? [String: Any] ?? [:]
        setValue(value, at: Array(path.dropFirst()), in: &nested)
        dict[first] = nested
    }

    private static func value(at path: [String], in dict: [String: Any]) -> Any? {
        guard let first = path.first else { return nil }
        if path.count == 1 { return dict[first] }
        guard let nested = dict[first] as? [String: Any] else { return nil }
        return value(at: Array(path.dropFirst()), in: nested)
    }

    private static func yamlEqual(_ lhs: Any?, _ rhs: Any) -> Bool {
        switch (lhs, rhs) {
        case let (l as Int, r as Int):
            return l == r
        case let (l as Double, r as Double):
            return l == r
        case let (l as Int, r as Double):
            return Double(l) == r
        case let (l as Double, r as Int):
            return l == Double(r)
        case let (l as String, r as String):
            return l == r
        case let (l as Bool, r as Bool):
            return l == r
        case let (l as [String: Any], r as [String: Any]):
            guard l.keys.count == r.keys.count else { return false }
            return l.keys.allSatisfy { key in
                guard let rv = r[key] else { return false }
                return yamlEqual(l[key] as Any?, rv)
            }
        case let (l as [Any], r as [Any]):
            guard l.count == r.count else { return false }
            return zip(l, r).allSatisfy { yamlEqual($0, $1) }
        default:
            return false
        }
    }
}

