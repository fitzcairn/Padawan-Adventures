import Foundation
import os
import Yams

private let levelCatalogLogger = Logger(subsystem: "PadawanAdventures", category: "LevelCatalog")

/// A gate puzzle vocabulary entry: spelled word + pronunciation track basename.
nonisolated struct GateWord: Equatable, Sendable {
    var word: String
    var sound: String
}

/// Per-level gate letter-puzzle settings from `gate:` in level YAML.
nonisolated struct GatePuzzleConfig: Decodable, Equatable, Sendable {
    var timerSeconds: Double
    /// Max seconds between word-sound plays before auto-replay.
    var wordSoundRepeatSeconds: Double
    /// Track basename played when the puzzle is solved.
    var winSound: String
    /// Extra random letters beyond the chosen word (total sprites = word length + this).
    var numPaddingLetters: Int
    /// Sorted by word for deterministic RNG over map-decoded YAML.
    var words: [GateWord]

    enum CodingKeys: String, CodingKey {
        case timerSeconds = "timer_seconds"
        case wordSoundRepeatSeconds = "word_sound_repeat_seconds"
        case winSound = "win_sound"
        case numPaddingLetters = "num_padding_letters"
        case words
    }

    nonisolated static let fallback = GatePuzzleConfig(
        timerSeconds: 30,
        wordSoundRepeatSeconds: 10,
        winSound: "sfx_gate_win",
        numPaddingLetters: 6,
        words: [
            .init(word: "cat", sound: "sfx_word_cat"),
            .init(word: "dog", sound: "sfx_word_dog"),
            .init(word: "gate", sound: "sfx_word_gate"),
            .init(word: "open", sound: "sfx_word_open"),
            .init(word: "star", sound: "sfx_word_star"),
        ]
    )

    nonisolated init(
        timerSeconds: Double,
        wordSoundRepeatSeconds: Double = 10,
        winSound: String = "sfx_gate_win",
        numPaddingLetters: Int = 6,
        words: [GateWord]
    ) {
        self.timerSeconds = timerSeconds
        self.wordSoundRepeatSeconds = wordSoundRepeatSeconds
        self.winSound = winSound.trimmingCharacters(in: .whitespacesAndNewlines)
        self.numPaddingLetters = numPaddingLetters
        self.words = Self.normalizedWords(words)
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timerSeconds = try container.decodeIfPresent(Double.self, forKey: .timerSeconds)
            ?? Self.fallback.timerSeconds
        wordSoundRepeatSeconds = try container.decodeIfPresent(
            Double.self,
            forKey: .wordSoundRepeatSeconds
        ) ?? Self.fallback.wordSoundRepeatSeconds
        winSound = (
            try container.decodeIfPresent(String.self, forKey: .winSound)
                ?? Self.fallback.winSound
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        numPaddingLetters = try container.decodeIfPresent(Int.self, forKey: .numPaddingLetters)
            ?? Self.fallback.numPaddingLetters

        if let map = try container.decodeIfPresent([String: String].self, forKey: .words) {
            words = Self.normalizedWords(
                map.map { GateWord(word: $0.key, sound: $0.value) }
            )
        } else {
            words = Self.fallback.words
        }
    }

    func validate() throws {
        guard timerSeconds > 0 else {
            throw WorldSeedError.invalidGateTimer(timerSeconds)
        }
        guard wordSoundRepeatSeconds > 0 else {
            throw WorldSeedError.invalidGateWordSoundRepeat(wordSoundRepeatSeconds)
        }
        guard numPaddingLetters >= 0 else {
            throw WorldSeedError.invalidGatePaddingLetters(numPaddingLetters)
        }
        guard !winSound.isEmpty else {
            throw WorldSeedError.invalidGateWords
        }
        guard !words.isEmpty else {
            throw WorldSeedError.invalidGateWords
        }
        let letterSet = CharacterSet.letters
        for entry in words {
            guard !entry.word.isEmpty,
                  entry.word.unicodeScalars.allSatisfy({ letterSet.contains($0) }),
                  !entry.sound.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw WorldSeedError.invalidGateWords
            }
        }
    }

    private static func normalizedWords(_ words: [GateWord]) -> [GateWord] {
        words
            .map {
                GateWord(
                    word: $0.word.lowercased(),
                    sound: $0.sound.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .sorted { $0.word < $1.word }
    }
}

/// A destructible-wall puzzle letter: glyph + pronunciation/name track basenames.
nonisolated struct DestructibleWallLetter: Equatable, Sendable {
    var letter: String
    var pronunciation: String
    var name: String
}

/// Per-level destructible-wall letter-matching settings from `destructible_wall:` in level YAML.
nonisolated struct DestructibleWallPuzzleConfig: Decodable, Equatable, Sendable {
    var timerSeconds: Double
    /// Max seconds between target-pronunciation plays before auto-replay.
    var letterSoundRepeatSeconds: Double
    /// Seconds after an incorrect tap before replaying the target pronunciation.
    var incorrectReplayDelaySeconds: Double
    /// Expected number of letters chosen for a round (sampled in `1...letters.count`).
    var letterCountMean: Double
    /// Track basename played on each correct match (“yay!”).
    var winSound: String
    /// Sorted by letter for deterministic RNG over map-decoded YAML.
    var letters: [DestructibleWallLetter]

    enum CodingKeys: String, CodingKey {
        case timerSeconds = "timer_seconds"
        case letterSoundRepeatSeconds = "letter_sound_repeat_seconds"
        case incorrectReplayDelaySeconds = "incorrect_replay_delay_seconds"
        case letterCountMean = "letter_count_mean"
        case winSound = "win_sound"
        case letters
    }

    private struct LetterSoundsDTO: Decodable {
        var pronunciation: String
        var name: String
    }

    nonisolated static let fallback = DestructibleWallPuzzleConfig(
        timerSeconds: 30,
        letterSoundRepeatSeconds: 3,
        incorrectReplayDelaySeconds: 1,
        letterCountMean: 4,
        winSound: "sfx_wall_yay",
        letters: [
            .init(letter: "a", pronunciation: "sfx_letter_a_pronunciation", name: "sfx_letter_a_name"),
            .init(letter: "b", pronunciation: "sfx_letter_b_pronunciation", name: "sfx_letter_b_name"),
            .init(letter: "c", pronunciation: "sfx_letter_c_pronunciation", name: "sfx_letter_c_name"),
            .init(letter: "d", pronunciation: "sfx_letter_d_pronunciation", name: "sfx_letter_d_name"),
            .init(letter: "e", pronunciation: "sfx_letter_e_pronunciation", name: "sfx_letter_e_name"),
            .init(letter: "f", pronunciation: "sfx_letter_f_pronunciation", name: "sfx_letter_f_name"),
            .init(letter: "g", pronunciation: "sfx_letter_g_pronunciation", name: "sfx_letter_g_name"),
            .init(letter: "h", pronunciation: "sfx_letter_h_pronunciation", name: "sfx_letter_h_name"),
        ]
    )

    nonisolated init(
        timerSeconds: Double,
        letterSoundRepeatSeconds: Double = 3,
        incorrectReplayDelaySeconds: Double = 1,
        letterCountMean: Double = 4,
        winSound: String = "sfx_wall_yay",
        letters: [DestructibleWallLetter]
    ) {
        self.timerSeconds = timerSeconds
        self.letterSoundRepeatSeconds = letterSoundRepeatSeconds
        self.incorrectReplayDelaySeconds = incorrectReplayDelaySeconds
        self.letterCountMean = letterCountMean
        self.winSound = winSound.trimmingCharacters(in: .whitespacesAndNewlines)
        self.letters = Self.normalizedLetters(letters)
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timerSeconds = try container.decodeIfPresent(Double.self, forKey: .timerSeconds)
            ?? Self.fallback.timerSeconds
        letterSoundRepeatSeconds = try container.decodeIfPresent(
            Double.self,
            forKey: .letterSoundRepeatSeconds
        ) ?? Self.fallback.letterSoundRepeatSeconds
        incorrectReplayDelaySeconds = try container.decodeIfPresent(
            Double.self,
            forKey: .incorrectReplayDelaySeconds
        ) ?? Self.fallback.incorrectReplayDelaySeconds
        letterCountMean = try container.decodeIfPresent(Double.self, forKey: .letterCountMean)
            ?? Self.fallback.letterCountMean
        winSound = (
            try container.decodeIfPresent(String.self, forKey: .winSound)
                ?? Self.fallback.winSound
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        if let map = try container.decodeIfPresent([String: LetterSoundsDTO].self, forKey: .letters) {
            letters = Self.normalizedLetters(
                map.map {
                    DestructibleWallLetter(
                        letter: $0.key,
                        pronunciation: $0.value.pronunciation,
                        name: $0.value.name
                    )
                }
            )
        } else {
            letters = Self.fallback.letters
        }
    }

    func validate() throws {
        guard timerSeconds > 0 else {
            throw WorldSeedError.invalidDestructibleWallTimer(timerSeconds)
        }
        guard letterSoundRepeatSeconds > 0 else {
            throw WorldSeedError.invalidDestructibleWallLetterSoundRepeat(letterSoundRepeatSeconds)
        }
        guard incorrectReplayDelaySeconds > 0 else {
            throw WorldSeedError.invalidDestructibleWallIncorrectReplayDelay(incorrectReplayDelaySeconds)
        }
        guard letterCountMean >= 1 else {
            throw WorldSeedError.invalidDestructibleWallLetterCountMean(letterCountMean)
        }
        guard !winSound.isEmpty else {
            throw WorldSeedError.invalidDestructibleWallLetters
        }
        guard !letters.isEmpty else {
            throw WorldSeedError.invalidDestructibleWallLetters
        }
        let letterSet = CharacterSet.letters
        var seen = Set<String>()
        for entry in letters {
            guard entry.letter.count == 1,
                  entry.letter.unicodeScalars.allSatisfy({ letterSet.contains($0) }),
                  !entry.pronunciation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !entry.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  seen.insert(entry.letter).inserted else {
                throw WorldSeedError.invalidDestructibleWallLetters
            }
        }
    }

    private static func normalizedLetters(_ letters: [DestructibleWallLetter]) -> [DestructibleWallLetter] {
        letters
            .map {
                DestructibleWallLetter(
                    letter: $0.letter.lowercased(),
                    pronunciation: $0.pronunciation.trimmingCharacters(in: .whitespacesAndNewlines),
                    name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .sorted { $0.letter < $1.letter }
    }
}

/// Per-level map size and generation settings loaded from `base_level.yaml` / `Levels/*.yaml`.
nonisolated struct LevelConfig: Decodable, Equatable, Sendable {
    var name: String
    /// Raw `music:` value; interpret with `MusicCue.parse`.
    var music: String?
    /// Shared letter-name prompt replay interval (combat cues, wall puzzle, etc.).
    var letterSoundRepeatSeconds: Double
    /// Max seconds a combat slash stays active after the initial tap.
    var slashMaxSeconds: Double
    var width: Int
    var height: Int
    var algorithm: String
    var roomCount: Int
    var corridorWidth: Int
    var room: WorldSeedConfig.RoomParams
    var pickups: WorldSeedConfig.PickupsSpawnConfig?
    /// Optional per-level overrides for `world.yaml` `fx:` (merged per event key).
    var fx: SoundEffectTable?
    var gate: GatePuzzleConfig
    var destructibleWall: DestructibleWallPuzzleConfig

    enum CodingKeys: String, CodingKey {
        case name
        case music
        case letterSoundRepeatSeconds = "letter_sound_repeat_seconds"
        case slashMaxSeconds = "slash_max_seconds"
        case width
        case height
        case algorithm
        case roomCount = "room_count"
        case corridorWidth = "corridor_width"
        case room
        case pickups
        case fx
        case gate
        case destructibleWall = "destructible_wall"
    }

    nonisolated static let fallbackSlashMaxSeconds: Double = 0.5

    nonisolated static let fallback = LevelConfig(
        name: "Level 1",
        music: "level_theme",
        letterSoundRepeatSeconds: 3,
        slashMaxSeconds: fallbackSlashMaxSeconds,
        width: 100,
        height: 100,
        algorithm: "rooms_doors",
        roomCount: 100,
        corridorWidth: 2,
        room: .init(
            minRoomSize: 4,
            maxRoomSize: 12,
            pitChance: 0.2,
            pitMeanSize: 2,
            pitMaxSize: 5,
            wallDestructibleChance: 0.8,
            gateChance: 0.5
        ),
        pickups: .init(
            health: .init(spawnChancePerRoom: 0.8),
            energy: .init(spawnChancePerRoom: 0.8)
        ),
        fx: nil,
        gate: .fallback,
        destructibleWall: .fallback
    )

    nonisolated init(
        name: String,
        music: String? = nil,
        letterSoundRepeatSeconds: Double = 3,
        slashMaxSeconds: Double = fallbackSlashMaxSeconds,
        width: Int,
        height: Int,
        algorithm: String,
        roomCount: Int,
        corridorWidth: Int,
        room: WorldSeedConfig.RoomParams,
        pickups: WorldSeedConfig.PickupsSpawnConfig? = nil,
        fx: SoundEffectTable? = nil,
        gate: GatePuzzleConfig = .fallback,
        destructibleWall: DestructibleWallPuzzleConfig = .fallback
    ) {
        self.name = name
        self.music = music
        self.letterSoundRepeatSeconds = letterSoundRepeatSeconds
        self.slashMaxSeconds = slashMaxSeconds
        self.width = width
        self.height = height
        self.algorithm = algorithm
        self.roomCount = roomCount
        self.corridorWidth = corridorWidth
        self.room = room
        self.pickups = pickups
        self.fx = fx
        self.gate = gate
        self.destructibleWall = destructibleWall
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        music = try container.decodeIfPresent(String.self, forKey: .music)
        width = try container.decode(Int.self, forKey: .width)
        height = try container.decode(Int.self, forKey: .height)
        algorithm = try container.decode(String.self, forKey: .algorithm)
        roomCount = try container.decode(Int.self, forKey: .roomCount)
        corridorWidth = try container.decode(Int.self, forKey: .corridorWidth)
        room = try container.decode(WorldSeedConfig.RoomParams.self, forKey: .room)
        pickups = try container.decodeIfPresent(WorldSeedConfig.PickupsSpawnConfig.self, forKey: .pickups)
        fx = try container.decodeIfPresent(SoundEffectTable.self, forKey: .fx)
        gate = try container.decodeIfPresent(GatePuzzleConfig.self, forKey: .gate) ?? .fallback
        let decodedWall = try container.decodeIfPresent(
            DestructibleWallPuzzleConfig.self,
            forKey: .destructibleWall
        ) ?? .fallback
        let topLevelRepeat = try container.decodeIfPresent(
            Double.self,
            forKey: .letterSoundRepeatSeconds
        )
        // Top-level shared cadence wins; otherwise keep wall-nested / fallback value.
        letterSoundRepeatSeconds = topLevelRepeat ?? decodedWall.letterSoundRepeatSeconds
        if let topLevelRepeat {
            destructibleWall = DestructibleWallPuzzleConfig(
                timerSeconds: decodedWall.timerSeconds,
                letterSoundRepeatSeconds: topLevelRepeat,
                incorrectReplayDelaySeconds: decodedWall.incorrectReplayDelaySeconds,
                letterCountMean: decodedWall.letterCountMean,
                winSound: decodedWall.winSound,
                letters: decodedWall.letters
            )
        } else {
            destructibleWall = decodedWall
        }
        slashMaxSeconds = try container.decodeIfPresent(Double.self, forKey: .slashMaxSeconds)
            ?? Self.fallbackSlashMaxSeconds
    }

    func validate() throws {
        guard letterSoundRepeatSeconds > 0 else {
            throw WorldSeedError.invalidDestructibleWallLetterSoundRepeat(letterSoundRepeatSeconds)
        }
        guard slashMaxSeconds > 0 else {
            throw WorldSeedError.invalidSlashMaxSeconds(slashMaxSeconds)
        }
        try gate.validate()
        try destructibleWall.validate()
    }

    var musicCue: MusicCue {
        MusicCue.parse(music)
    }

    var generation: WorldSeedConfig.GenerationParams {
        .init(
            algorithm: algorithm,
            roomCount: roomCount,
            corridorWidth: corridorWidth,
            room: room
        )
    }

    static func loadFromBundle(
        named name: String = "base_level",
        withExtension ext: String = "yaml",
        subdirectory: String? = nil
    ) throws -> LevelConfig {
        let data = try resourceData(named: name, withExtension: ext, subdirectory: subdirectory)
        return try decode(
            from: data,
            parentDataNamed: { parentName in
                // Inherited bases live at the Resources root.
                try resourceData(named: parentName, withExtension: ext, subdirectory: nil)
            }
        )
    }

    /// Decodes YAML, resolving `inherits:` via `parentDataNamed` when provided (or required).
    static func decode(
        from data: Data,
        parentDataNamed: ((String) throws -> Data)? = nil
    ) throws -> LevelConfig {
        do {
            let merged = try resolveInheritance(
                from: data,
                parentDataNamed: parentDataNamed,
                visited: []
            )
            let yaml = try Yams.dump(object: merged)
            let level = try YAMLDecoder().decode(LevelConfig.self, from: yaml)
            try level.validate()
            return level
        } catch let error as WorldSeedError {
            throw error
        } catch {
            throw WorldSeedError.decodeFailed(String(describing: error))
        }
    }

    static func decode(from yaml: String) throws -> LevelConfig {
        try decode(from: Data(yaml.utf8))
    }

    /// Test/helper entry that resolves `inherits:` against in-memory parent YAML documents.
    static func decode(
        from yaml: String,
        parents: [String: String]
    ) throws -> LevelConfig {
        try decode(
            from: Data(yaml.utf8),
            parentDataNamed: { name in
                guard let parentYAML = parents[name] else {
                    throw WorldSeedError.missingResource
                }
                return Data(parentYAML.utf8)
            }
        )
    }

    nonisolated static func deepMerge(
        _ base: [String: Any],
        overwriting child: [String: Any]
    ) -> [String: Any] {
        var result = base
        for (key, value) in child {
            if let childDict = asStringKeyedDictionary(value),
               let baseDict = asStringKeyedDictionary(result[key] as Any?) {
                result[key] = deepMerge(baseDict, overwriting: childDict)
            } else {
                result[key] = normalizeYAMLValue(value)
            }
        }
        return result
    }

    private static func resolveInheritance(
        from data: Data,
        parentDataNamed: ((String) throws -> Data)?,
        visited: Set<String>
    ) throws -> [String: Any] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw WorldSeedError.decodeFailed("level YAML is not valid UTF-8")
        }
        guard let loaded = try Yams.load(yaml: text),
              let dict = asStringKeyedDictionary(loaded) else {
            throw WorldSeedError.decodeFailed("level YAML did not decode to a dictionary")
        }

        var working = dict
        guard let inherits = working["inherits"] as? String else {
            return working
        }

        let parentName = (inherits as NSString).deletingPathExtension
        guard !visited.contains(parentName) else {
            throw WorldSeedError.decodeFailed("circular inherits involving '\(parentName)'")
        }
        guard let parentDataNamed else {
            throw WorldSeedError.missingResource
        }

        let parentData = try parentDataNamed(parentName)
        let resolvedParent = try resolveInheritance(
            from: parentData,
            parentDataNamed: parentDataNamed,
            visited: visited.union([parentName])
        )

        working.removeValue(forKey: "inherits")
        return deepMerge(resolvedParent, overwriting: working)
    }

    private static func resourceData(
        named name: String,
        withExtension ext: String,
        subdirectory: String?
    ) throws -> Data {
        // Prefer subdirectory when present; fall back to bundle root because Xcode may flatten
        // Resources/Levels/*.yaml into the app bundle root.
        if let subdirectory,
           let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdirectory) {
            return try Data(contentsOf: url)
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            throw WorldSeedError.missingResource
        }
        return try Data(contentsOf: url)
    }

    private static func asStringKeyedDictionary(_ value: Any?) -> [String: Any]? {
        guard let value else { return nil }
        if let dict = value as? [String: Any] {
            return dict.mapValues { normalizeYAMLValue($0) }
        }
        if let dict = value as? NSDictionary {
            var result: [String: Any] = [:]
            for (key, nested) in dict {
                guard let stringKey = key as? String else { continue }
                result[stringKey] = normalizeYAMLValue(nested)
            }
            return result
        }
        return nil
    }

    private static func normalizeYAMLValue(_ value: Any) -> Any {
        if let dict = asStringKeyedDictionary(value) {
            return dict
        }
        if let array = value as? [Any] {
            return array.map { normalizeYAMLValue($0) }
        }
        if let array = value as? NSArray {
            return array.map { normalizeYAMLValue($0) }
        }
        return value
    }
}

/// A playable level discovered from `Resources/Levels/`.
nonisolated struct LevelDescriptor: Equatable, Sendable {
    let resourceName: String
    let displayName: String
}

nonisolated enum LevelCatalog {
    static let subdirectory = "Levels"

    static func loadFromBundle(
        withExtension ext: String = "yaml"
    ) -> [LevelDescriptor] {
        let urls = levelResourceURLs(withExtension: ext)

        return urls.compactMap { url -> LevelDescriptor? in
            let resourceName = url.deletingPathExtension().lastPathComponent
            do {
                let level = try LevelConfig.loadFromBundle(
                    named: resourceName,
                    withExtension: ext,
                    subdirectory: subdirectory
                )
                return LevelDescriptor(resourceName: resourceName, displayName: level.name)
            } catch {
                levelCatalogLogger.error(
                    "Failed to load level '\(resourceName, privacy: .public)': \(String(describing: error), privacy: .public)"
                )
                return nil
            }
        }
        .sorted { $0.resourceName < $1.resourceName }
    }

    private static func levelResourceURLs(withExtension ext: String) -> [URL] {
        if let nested = Bundle.main.urls(
            forResourcesWithExtension: ext,
            subdirectory: subdirectory
        ), !nested.isEmpty {
            return nested
        }

        // Flattened bundle layout: keep only playable `level_*.yaml` files at the root.
        let root = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) ?? []
        return root.filter { url in
            url.deletingPathExtension().lastPathComponent.hasPrefix("level_")
        }
    }
}
