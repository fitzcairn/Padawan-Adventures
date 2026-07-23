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
    var wallsBlownUp: Int
    var pitsCrossed: Int
    var enemiesKilled: Int
    var extras: [String: Int]

    init(
        gatesOpened: Int = 0,
        wallsBlownUp: Int = 0,
        pitsCrossed: Int = 0,
        enemiesKilled: Int = 0,
        extras: [String: Int] = [:]
    ) {
        self.gatesOpened = gatesOpened
        self.wallsBlownUp = wallsBlownUp
        self.pitsCrossed = pitsCrossed
        self.enemiesKilled = enemiesKilled
        self.extras = extras
    }

    private enum CodingKeys: String, CodingKey {
        case gatesOpened
        case wallsBlownUp
        case pitsCrossed
        case enemiesKilled
        case extras
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gatesOpened = try container.decodeIfPresent(Int.self, forKey: .gatesOpened) ?? 0
        wallsBlownUp = try container.decodeIfPresent(Int.self, forKey: .wallsBlownUp) ?? 0
        pitsCrossed = try container.decodeIfPresent(Int.self, forKey: .pitsCrossed) ?? 0
        enemiesKilled = try container.decodeIfPresent(Int.self, forKey: .enemiesKilled) ?? 0
        extras = try container.decodeIfPresent([String: Int].self, forKey: .extras) ?? [:]
    }
}

/// Per-player settings from the Settings screen. New fields decode with defaults.
nonisolated struct PlayerSettings: Codable, Equatable, Sendable {
    var soundEffectsEnabled: Bool
    var soundEffectsVolume: Float
    var musicEnabled: Bool
    var musicVolume: Float

    static let `default` = PlayerSettings()

    init(
        soundEffectsEnabled: Bool = true,
        soundEffectsVolume: Float = 1,
        musicEnabled: Bool = true,
        musicVolume: Float = 1
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
            try container.decodeIfPresent(Float.self, forKey: .musicVolume) ?? 1
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

    init(
        version: Int = PlayerGameState.currentVersion,
        lastLevelStarted: String? = nil,
        levels: [String: LevelProgress] = [:],
        health: Int,
        energy: Int,
        inventory: PlayerInventory = PlayerInventory(),
        stats: PlayerStats = PlayerStats(),
        totalStars: Int = 0,
        settings: PlayerSettings = .default
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

    /// Clears run progress for a fresh game (inventory, stars, level flags) and restores starting vitals.
    mutating func resetForNewGame(health: Int, energy: Int) {
        lastLevelStarted = nil
        levels = [:]
        inventory = PlayerInventory()
        totalStars = 0
        resetVitals(health: health, energy: energy)
    }
}
