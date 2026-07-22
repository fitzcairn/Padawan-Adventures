import Foundation

/// Empty placeholder for future inventory contents.
nonisolated struct PlayerInventory: Codable, Equatable, Sendable {
    init() {}
}

/// Per-level progress. New fields should decode with defaults via `decodeIfPresent`.
nonisolated struct LevelProgress: Codable, Equatable, Sendable {
    var started: Bool
    var completed: Bool
    var starsEarned: Int

    init(started: Bool = false, completed: Bool = false, starsEarned: Int = 0) {
        self.started = started
        self.completed = completed
        self.starsEarned = starsEarned
    }

    private enum CodingKeys: String, CodingKey {
        case started
        case completed
        case starsEarned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        started = try container.decodeIfPresent(Bool.self, forKey: .started) ?? false
        completed = try container.decodeIfPresent(Bool.self, forKey: .completed) ?? false
        starsEarned = try container.decodeIfPresent(Int.self, forKey: .starsEarned) ?? 0
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

    init(
        version: Int = PlayerGameState.currentVersion,
        lastLevelStarted: String? = nil,
        levels: [String: LevelProgress] = [:],
        health: Int,
        energy: Int,
        inventory: PlayerInventory = PlayerInventory(),
        stats: PlayerStats = PlayerStats()
    ) {
        self.version = version
        self.lastLevelStarted = lastLevelStarted
        self.levels = levels
        self.health = health
        self.energy = energy
        self.inventory = inventory
        self.stats = stats
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case lastLevelStarted
        case levels
        case health
        case energy
        case inventory
        case stats
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
    }

    mutating func markLevelStarted(_ resourceName: String) {
        lastLevelStarted = resourceName
        var progress = levels[resourceName] ?? LevelProgress()
        progress.started = true
        levels[resourceName] = progress
    }

    mutating func markLevelCompleted(_ resourceName: String) {
        var progress = levels[resourceName] ?? LevelProgress()
        progress.started = true
        progress.completed = true
        levels[resourceName] = progress
    }

    mutating func syncVitals(from world: GameWorld) {
        health = world.healthCount
        energy = world.energyCount
    }
}
