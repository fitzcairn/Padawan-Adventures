import Foundation

/// Persistent collectibles earned by completing levels.
nonisolated struct PlayerInventory: Codable, Equatable, Sendable {
    /// Ordered unique artifact IDs (SF Symbol names for now).
    var artifacts: [String]

    init(artifacts: [String] = []) {
        self.artifacts = artifacts
    }

    private enum CodingKeys: String, CodingKey {
        case artifacts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        artifacts = try container.decodeIfPresent([String].self, forKey: .artifacts) ?? []
    }

    mutating func addArtifact(_ id: String) {
        guard !id.isEmpty, !artifacts.contains(id) else { return }
        artifacts.append(id)
    }
}

/// Result of banking a level run into the player's best score.
nonisolated struct LevelStarsFinalizeResult: Equatable, Sendable {
    var didBeatPrevious: Bool
    var previousBest: Int
    var newScore: Int
}

/// Per-level progress. New fields should decode with defaults via `decodeIfPresent`.
nonisolated struct LevelProgress: Codable, Equatable, Sendable {
    var started: Bool
    var completed: Bool
    /// Best completed star count for this level.
    var starsEarned: Int
    /// In-progress run stars shown in the HUD.
    var starsCurrent: Int

    init(
        started: Bool = false,
        completed: Bool = false,
        starsEarned: Int = 0,
        starsCurrent: Int = 0
    ) {
        self.started = started
        self.completed = completed
        self.starsEarned = starsEarned
        self.starsCurrent = starsCurrent
    }

    private enum CodingKeys: String, CodingKey {
        case started
        case completed
        case starsEarned
        case starsCurrent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        started = try container.decodeIfPresent(Bool.self, forKey: .started) ?? false
        completed = try container.decodeIfPresent(Bool.self, forKey: .completed) ?? false
        starsEarned = try container.decodeIfPresent(Int.self, forKey: .starsEarned) ?? 0
        starsCurrent = try container.decodeIfPresent(Int.self, forKey: .starsCurrent) ?? 0
    }
}

/// Cumulative encounter stats. Known counters plus an extensible extras bag.
nonisolated struct PlayerStats: Codable, Equatable, Sendable {
    var gatesOpened: Int
    var pitsCrossed: Int
    var enemiesKilled: Int
    var extras: [String: Int]

    init(
        gatesOpened: Int = 0,
        pitsCrossed: Int = 0,
        enemiesKilled: Int = 0,
        extras: [String: Int] = [:]
    ) {
        self.gatesOpened = gatesOpened
        self.pitsCrossed = pitsCrossed
        self.enemiesKilled = enemiesKilled
        self.extras = extras
    }

    private enum CodingKeys: String, CodingKey {
        case gatesOpened
        case pitsCrossed
        case enemiesKilled
        case extras
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gatesOpened = try container.decodeIfPresent(Int.self, forKey: .gatesOpened) ?? 0
        pitsCrossed = try container.decodeIfPresent(Int.self, forKey: .pitsCrossed) ?? 0
        enemiesKilled = try container.decodeIfPresent(Int.self, forKey: .enemiesKilled) ?? 0
        extras = try container.decodeIfPresent([String: Int].self, forKey: .extras) ?? [:]
    }
}

/// Per-player settings from the Settings screen. New fields decode with defaults.
nonisolated struct PlayerSettings: Codable, Equatable, Sendable {
    /// Default BGM level — kept well below full SFX so gameplay audio stays clear.
    static let defaultMusicVolume: Float = 0.35

    var soundEffectsEnabled: Bool
    var soundEffectsVolume: Float
    var musicEnabled: Bool
    var musicVolume: Float

    static let `default` = PlayerSettings()

    init(
        soundEffectsEnabled: Bool = true,
        soundEffectsVolume: Float = 1,
        musicEnabled: Bool = true,
        musicVolume: Float = PlayerSettings.defaultMusicVolume
    ) {
        self.soundEffectsEnabled = soundEffectsEnabled
        self.soundEffectsVolume = Self.clamp(soundEffectsVolume)
        self.musicEnabled = musicEnabled
        self.musicVolume = Self.clamp(musicVolume)
    }

    private enum CodingKeys: String, CodingKey {
        case soundEffectsEnabled
        case soundEffectsVolume
        case musicEnabled
        case musicVolume
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        soundEffectsEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundEffectsEnabled) ?? true
        soundEffectsVolume = Self.clamp(
            try container.decodeIfPresent(Float.self, forKey: .soundEffectsVolume) ?? 1
        )
        musicEnabled = try container.decodeIfPresent(Bool.self, forKey: .musicEnabled) ?? true
        musicVolume = Self.clamp(
            try container.decodeIfPresent(Float.self, forKey: .musicVolume) ?? Self.defaultMusicVolume
        )
    }

    private static func clamp(_ value: Float) -> Float {
        min(1, max(0, value))
    }
}

/// Persistent per-player meta state stored alongside the mid-run world save.
nonisolated struct PlayerGameState: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int
    /// `LevelDescriptor.resourceName` of the last level the player started.
    var lastLevelStarted: String?
    /// Progress keyed by `LevelDescriptor.resourceName`.
    var levels: [String: LevelProgress]
    var health: Int
    var energy: Int
    var inventory: PlayerInventory
    var stats: PlayerStats
    /// Sum of banked per-level bests (`starsEarned`).
    var totalStars: Int
    /// Settings screen values for this player.
    var settings: PlayerSettings
    /// One-shot Dad mode unlock; cleared after a level tap or new game.
    var dadModeUnlocked: Bool
    /// Minigame `kind` raw values (e.g. "ending-sound-pit") whose tutorial
    /// has already been shown. Cleared by `resetForNewGame`.
    var seenMinigameTutorials: Set<String>
    /// Whether the level-1 world tap/drag tutorial has been shown. Cleared by `resetForNewGame`.
    var seenWorldTutorial: Bool
    /// Three merchant loadout slots. Empty string means vacant (plist cannot store `nil` in arrays).
    var itemSlots: [String]

    static let itemSlotCount = 3

    init(
        version: Int = PlayerGameState.currentVersion,
        lastLevelStarted: String? = nil,
        levels: [String: LevelProgress] = [:],
        health: Int,
        energy: Int,
        inventory: PlayerInventory = PlayerInventory(),
        stats: PlayerStats = PlayerStats(),
        totalStars: Int = 0,
        settings: PlayerSettings = .default,
        dadModeUnlocked: Bool = false,
        seenMinigameTutorials: Set<String> = [],
        seenWorldTutorial: Bool = false,
        itemSlots: [String] = PlayerGameState.emptyItemSlots
    ) {
        self.version = version
        self.lastLevelStarted = lastLevelStarted
        self.levels = levels
        self.health = health
        self.energy = energy
        self.inventory = inventory
        self.stats = stats
        self.totalStars = totalStars
        self.settings = settings
        self.dadModeUnlocked = dadModeUnlocked
        self.seenMinigameTutorials = seenMinigameTutorials
        self.seenWorldTutorial = seenWorldTutorial
        self.itemSlots = Self.normalizedItemSlots(itemSlots)
    }

    static var emptyItemSlots: [String] {
        Array(repeating: "", count: itemSlotCount)
    }

    static func normalizedItemSlots(_ slots: [String]) -> [String] {
        var result = slots
        if result.count < itemSlotCount {
            result.append(contentsOf: Array(repeating: "", count: itemSlotCount - result.count))
        } else if result.count > itemSlotCount {
            result = Array(result.prefix(itemSlotCount))
        }
        return result
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case lastLevelStarted
        case levels
        case health
        case energy
        case inventory
        case stats
        case totalStars
        case settings
        case dadModeUnlocked
        case seenMinigameTutorials
        case seenWorldTutorial
        case itemSlots
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        lastLevelStarted = try container.decodeIfPresent(String.self, forKey: .lastLevelStarted)
        levels = try container.decodeIfPresent([String: LevelProgress].self, forKey: .levels) ?? [:]
        health = try container.decodeIfPresent(Int.self, forKey: .health) ?? 0
        energy = try container.decodeIfPresent(Int.self, forKey: .energy) ?? 0
        inventory = try container.decodeIfPresent(PlayerInventory.self, forKey: .inventory) ?? PlayerInventory()
        stats = try container.decodeIfPresent(PlayerStats.self, forKey: .stats) ?? PlayerStats()
        totalStars = try container.decodeIfPresent(Int.self, forKey: .totalStars) ?? 0
        settings = try container.decodeIfPresent(PlayerSettings.self, forKey: .settings) ?? .default
        dadModeUnlocked = try container.decodeIfPresent(Bool.self, forKey: .dadModeUnlocked) ?? false
        seenMinigameTutorials = try container.decodeIfPresent(
            Set<String>.self, forKey: .seenMinigameTutorials
        ) ?? []
        seenWorldTutorial = try container.decodeIfPresent(Bool.self, forKey: .seenWorldTutorial) ?? false
        itemSlots = Self.normalizedItemSlots(
            try container.decodeIfPresent([String].self, forKey: .itemSlots) ?? []
        )
    }

    mutating func markLevelStarted(_ resourceName: String) {
        lastLevelStarted = resourceName
        var progress = levels[resourceName] ?? LevelProgress()
        progress.started = true
        levels[resourceName] = progress
    }

    mutating func markLevelCompleted(_ resourceName: String, artifact: String? = nil) {
        var progress = levels[resourceName] ?? LevelProgress()
        progress.started = true
        progress.completed = true
        levels[resourceName] = progress
        if let artifact {
            inventory.addArtifact(artifact)
        }
    }

    mutating func resetLevelStarsCurrent(_ resourceName: String) {
        var progress = levels[resourceName] ?? LevelProgress()
        progress.starsCurrent = 0
        levels[resourceName] = progress
    }

    mutating func addLevelStar(_ resourceName: String) {
        addLevelStars(resourceName, count: 1)
    }

    mutating func addLevelStars(_ resourceName: String, count: Int) {
        guard count > 0 else { return }
        var progress = levels[resourceName] ?? LevelProgress()
        progress.starsCurrent += count
        levels[resourceName] = progress
    }

    /// Spends `count` from `starsCurrent`. Fails (no change) when the run cannot cover it.
    @discardableResult
    mutating func spendLevelStars(_ resourceName: String, count: Int) -> Bool {
        guard count > 0 else { return false }
        var progress = levels[resourceName] ?? LevelProgress()
        guard progress.starsCurrent >= count else { return false }
        progress.starsCurrent -= count
        levels[resourceName] = progress
        return true
    }

    func itemSlotID(at index: Int) -> String? {
        guard itemSlots.indices.contains(index) else { return nil }
        let id = itemSlots[index]
        return id.isEmpty ? nil : id
    }

    /// Writes `itemID` into `index`, destroying any occupant (no refund).
    mutating func setItemSlot(index: Int, itemID: String?) {
        itemSlots = Self.normalizedItemSlots(itemSlots)
        guard itemSlots.indices.contains(index) else { return }
        itemSlots[index] = itemID ?? ""
    }

    @discardableResult
    mutating func finalizeLevelStars(_ resourceName: String) -> LevelStarsFinalizeResult {
        var progress = levels[resourceName] ?? LevelProgress()
        let previousBest = progress.starsEarned
        let newScore = progress.starsCurrent
        let didBeatPrevious = newScore > previousBest
        if didBeatPrevious {
            totalStars += newScore - previousBest
            progress.starsEarned = newScore
            levels[resourceName] = progress
        }
        return LevelStarsFinalizeResult(
            didBeatPrevious: didBeatPrevious,
            previousBest: previousBest,
            newScore: newScore
        )
    }

    mutating func syncVitals(from world: GameWorld) {
        health = world.healthCount
        energy = world.energyCount
    }

    mutating func resetVitals(health: Int, energy: Int) {
        self.health = health
        self.energy = energy
    }

    func hasSeenMinigameTutorial(_ key: String) -> Bool {
        seenMinigameTutorials.contains(key)
    }

    /// Records `key` as seen. Returns false when it was already recorded.
    @discardableResult
    mutating func markMinigameTutorialSeen(_ key: String) -> Bool {
        seenMinigameTutorials.insert(key).inserted
    }

    /// Clears run progress for a fresh game (inventory, stars, level flags) and restores starting vitals.
    mutating func resetForNewGame(health: Int, energy: Int) {
        lastLevelStarted = nil
        levels = [:]
        inventory = PlayerInventory()
        totalStars = 0
        dadModeUnlocked = false
        seenMinigameTutorials = []
        seenWorldTutorial = false
        itemSlots = Self.emptyItemSlots
        resetVitals(health: health, energy: energy)
    }

    /// Marks every catalog level strictly before `resourceName` complete and grants their artifacts.
    /// Clears Dad mode (one-shot unlock).
    mutating func applyProgressionJump(
        upTo resourceName: String,
        orderedLevels: [String],
        artifactsByResource: [String: String]
    ) {
        guard let targetIndex = orderedLevels.firstIndex(of: resourceName) else {
            dadModeUnlocked = false
            return
        }
        for prior in orderedLevels.prefix(targetIndex) {
            markLevelCompleted(prior, artifact: artifactsByResource[prior])
        }
        dadModeUnlocked = false
    }
}
