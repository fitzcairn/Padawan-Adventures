import Foundation

/// Discriminator for which combat minigame an encounter runs. Raw values match YAML `type:`.
nonisolated enum CombatMinigameKind: String, Codable, Equatable, Sendable, CaseIterable {
    /// The original swipe-to-slash arena (`CombatScene`).
    case slash
    /// Tap-the-matching-ring deflect arena (`CombatDeflectScene`).
    case deflect
}

/// Per-entry config for the slash arena.
nonisolated struct CombatSlashConfig: Equatable, Sendable {
    var weight: Double
    /// Multiplier on combat letter spawn frequency vs derived baseline (`1.0` = unchanged).
    var letterSpawnMultiplier: Double
    /// Casing for combat projectile / cue letters.
    var letterCase: CombatLetterCase
    /// Letter-name prompt replay interval in seconds.
    var letterSoundRepeatSeconds: Double

    nonisolated static let fallback = CombatSlashConfig(weight: 1)

    nonisolated init(
        weight: Double = 1,
        letterSpawnMultiplier: Double = 1.0,
        letterCase: CombatLetterCase = .upper,
        letterSoundRepeatSeconds: Double = 3
    ) {
        self.weight = weight
        self.letterSpawnMultiplier = letterSpawnMultiplier
        self.letterCase = letterCase
        self.letterSoundRepeatSeconds = letterSoundRepeatSeconds
    }

    func validate() throws {
        guard letterSpawnMultiplier > 0 else {
            throw WorldSeedError.invalidCombatLetterSpawnRate(letterSpawnMultiplier)
        }
        guard letterSoundRepeatSeconds > 0 else {
            throw WorldSeedError.invalidLetterSoundRepeat(letterSoundRepeatSeconds)
        }
    }
}

/// Per-entry config for the deflect arena.
nonisolated struct CombatDeflectConfig: Equatable, Sendable {
    var weight: Double
    /// Monster hit points; also the star award on win.
    var monsterHP: Int
    /// Seconds for an orb to fly from the monster to the player.
    var orbTravelSeconds: Double
    /// Optional subset of shared catalog ids (`nil` = first `defaultRingCount` catalog entries).
    /// Order is meaningful: left to right on screen.
    var letterIDs: [String]?
    /// Resolved letters in `letterIDs` order. Populated via `resolveLetters(from:)`.
    /// Count (2…6) is the number of deflection circles drawn.
    var letters: [GateLetter]

    static let defaultMonsterHP = 5
    static let defaultOrbTravelSeconds: Double = 3
    static let minRingCount = 2
    static let maxRingCount = 6
    /// Used when YAML omits `letters:` (and for the code fallback).
    static let defaultRingCount = 3
    /// Back-compat alias for the default letter / ring count.
    static let ringCount = defaultRingCount

    nonisolated static let fallback = CombatDeflectConfig(
        weight: 1,
        letterIDs: ["a", "b", "c"],
        letters: Array(LetterCatalog.fallback.letters.prefix(defaultRingCount))
    )

    nonisolated init(
        weight: Double = 1,
        monsterHP: Int = defaultMonsterHP,
        orbTravelSeconds: Double = defaultOrbTravelSeconds,
        letterIDs: [String]? = nil,
        letters: [GateLetter] = []
    ) {
        self.weight = weight
        self.monsterHP = monsterHP
        self.orbTravelSeconds = orbTravelSeconds
        self.letterIDs = letterIDs?.map { $0.lowercased() }
        self.letters = letters
    }

    /// Resolves `letterIDs` against the shared catalog, preserving YAML order.
    /// Gate letter-match sorts its letters; ring order here is positional, so it must not.
    mutating func resolveLetters(from catalog: LetterCatalog) throws {
        let ids = letterIDs ?? catalog.letters.prefix(Self.defaultRingCount).map(\.letter)
        var resolved: [GateLetter] = []
        resolved.reserveCapacity(ids.count)
        for id in ids {
            guard let entry = catalog.letter(named: id) else {
                throw WorldSeedError.invalidCombatDeflectLetters
            }
            resolved.append(entry)
        }
        letters = resolved
    }

    func validate() throws {
        guard monsterHP >= 1 else {
            throw WorldSeedError.invalidCombatMonsterHP(monsterHP)
        }
        guard orbTravelSeconds > 0 else {
            throw WorldSeedError.invalidCombatOrbTravelSeconds(orbTravelSeconds)
        }
        guard (Self.minRingCount...Self.maxRingCount).contains(letters.count) else {
            throw WorldSeedError.invalidCombatDeflectLetters
        }
        try CatalogValidators.validateLetterEntries(
            letters,
            requirePronunciation: false,
            emptyError: .invalidCombatDeflectLetters,
            invalidEntryError: .invalidCombatDeflectLetters
        )
    }
}

/// Discriminated union over the combat minigame entries in level YAML.
nonisolated enum CombatMinigameConfig: Equatable, Sendable {
    case slash(CombatSlashConfig)
    case deflect(CombatDeflectConfig)

    var kind: CombatMinigameKind {
        switch self {
        case .slash: .slash
        case .deflect: .deflect
        }
    }

    /// Relative pick weight; negatives are rejected by `CombatConfig.validate()`.
    var weight: Double {
        switch self {
        case .slash(let config): config.weight
        case .deflect(let config): config.weight
        }
    }
}

/// Resolved combat host config from level YAML `combat:`.
nonisolated struct CombatConfig: Equatable, Sendable {
    /// Music track basename for combat minigames; `nil` → inherit from audio.yaml.
    var music: String?
    var minigames: [CombatMinigameConfig]

    /// Used when a level omits `combat:` entirely — slash only, preserving old behaviour.
    nonisolated static let fallback = CombatConfig(music: "combat", minigames: [.slash(.fallback)])

    nonisolated init(music: String? = nil, minigames: [CombatMinigameConfig]) {
        self.music = music
        self.minigames = minigames
    }

    func minigame(for kind: CombatMinigameKind) -> CombatMinigameConfig? {
        minigames.first { $0.kind == kind }
    }

    /// Weighted pick. Entries with weight 0 are never chosen unless every weight is 0,
    /// in which case the first entry wins so an encounter always has something to run.
    func pickMinigame(using rng: inout some RandomNumberGenerator) throws -> CombatMinigameConfig {
        guard !minigames.isEmpty else {
            throw WorldSeedError.decodeFailed("combat.minigames must not be empty")
        }
        guard let picked = WeightedPicker.pick(from: minigames, weight: \.weight, using: &rng) else {
            throw WorldSeedError.decodeFailed("combat.minigames must not be empty")
        }
        return picked
    }

    mutating func resolveLetters(from catalog: LetterCatalog) throws {
        for index in minigames.indices {
            if case .deflect(var config) = minigames[index] {
                try config.resolveLetters(from: catalog)
                minigames[index] = .deflect(config)
            }
        }
    }

    func validate() throws {
        guard !minigames.isEmpty else {
            throw WorldSeedError.decodeFailed("combat.minigames must not be empty")
        }
        var seenKinds = Set<CombatMinigameKind>()
        for entry in minigames {
            guard entry.weight >= 0 else {
                throw WorldSeedError.invalidCombatMinigameWeight(entry.weight)
            }
            guard seenKinds.insert(entry.kind).inserted else {
                throw WorldSeedError.decodeFailed(
                    "combat.minigames has duplicate type '\(entry.kind.rawValue)'"
                )
            }
            switch entry {
            case .slash(let config): try config.validate()
            case .deflect(let config): try config.validate()
            }
        }
    }
}
