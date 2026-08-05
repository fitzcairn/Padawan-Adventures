import Foundation

/// Discriminator for which combat minigame an encounter runs. Raw values match YAML `type:`.
nonisolated enum CombatMinigameKind: String, Codable, Equatable, Sendable, CaseIterable {
    /// The original swipe-to-slash arena (`CombatScene`).
    case slash = "grapheme-sound-combat"
    /// Tap-the-matching-ring deflect arena, keyed on the word's first grapheme (`CombatDeflectScene`).
    case startingSoundDeflect = "starting-sound-combat"
    /// Same arena, keyed on the word's last grapheme.
    case endingSoundDeflect = "ending-sound-combat"
}

/// Per-entry config for the slash arena.
nonisolated struct CombatSlashConfig: Equatable, Sendable {
    var weight: Double
    /// Extra non-matching letters launched alongside the cued one, per wave.
    var minDecoyCount: Int
    var maxDecoyCount: Int
    /// Casing for combat projectile / cue letters.
    var graphemeCase: CombatGraphemeCase
    /// Letter-name prompt replay interval in seconds.
    var graphemeSoundRepeatSeconds: Double

    nonisolated static let fallback = CombatSlashConfig(weight: 1)

    nonisolated init(
        weight: Double = 1,
        minDecoyCount: Int = CombatMinigameEngine.Config.defaultMinDecoyCount,
        maxDecoyCount: Int = CombatMinigameEngine.Config.defaultMaxDecoyCount,
        graphemeCase: CombatGraphemeCase = .upper,
        graphemeSoundRepeatSeconds: Double = 3
    ) {
        self.weight = weight
        self.minDecoyCount = minDecoyCount
        self.maxDecoyCount = maxDecoyCount
        self.graphemeCase = graphemeCase
        self.graphemeSoundRepeatSeconds = graphemeSoundRepeatSeconds
    }

    func validate() throws {
        guard minDecoyCount >= 1,
              maxDecoyCount >= minDecoyCount,
              maxDecoyCount <= 8 else {
            throw WorldSeedError.invalidCombatDecoyCount(min: minDecoyCount, max: maxDecoyCount)
        }
        guard graphemeSoundRepeatSeconds > 0 else {
            throw WorldSeedError.invalidGraphemeSoundRepeat(graphemeSoundRepeatSeconds)
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
    /// Which grapheme the ring must match: word start (`starting-sound-combat`)
    /// or word end (`ending-sound-combat`).
    var letterPosition: GateWordPlugLetterPosition
    /// Optional subset of shared catalog ids (`nil` = first `defaultRingCount` catalog entries).
    /// Order is meaningful: left to right on screen.
    var graphemeIDs: [String]?
    /// Resolved letters in `graphemeIDs` order. Populated via `resolveGraphemes(from:)`.
    /// Count (2…6) is the number of deflection circles drawn.
    var graphemes: [GateGrapheme]

    static let defaultMonsterHP = 5
    static let defaultOrbTravelSeconds: Double = 3
    static let minRingCount = 2
    static let maxRingCount = 6
    /// Used when YAML omits `graphemes:` (and for the code fallback).
    static let defaultRingCount = 3
    /// Back-compat alias for the default letter / ring count.
    static let ringCount = defaultRingCount

    nonisolated static let fallback = CombatDeflectConfig(
        weight: 1,
        graphemeIDs: ["a", "b", "c"],
        graphemes: Array(GraphemeCatalog.fallback.graphemes.prefix(defaultRingCount))
    )

    nonisolated init(
        weight: Double = 1,
        monsterHP: Int = defaultMonsterHP,
        orbTravelSeconds: Double = defaultOrbTravelSeconds,
        letterPosition: GateWordPlugLetterPosition = .starting,
        graphemeIDs: [String]? = nil,
        graphemes: [GateGrapheme] = []
    ) {
        self.weight = weight
        self.monsterHP = monsterHP
        self.orbTravelSeconds = orbTravelSeconds
        self.letterPosition = letterPosition
        self.graphemeIDs = graphemeIDs?.map { $0.lowercased() }
        self.graphemes = graphemes
    }

    /// Resolves `graphemeIDs` against the shared catalog, preserving YAML order.
    /// Gate letter-match sorts its letters; ring order here is positional, so it must not.
    mutating func resolveGraphemes(from catalog: GraphemeCatalog) throws {
        let ids = graphemeIDs ?? catalog.graphemes.prefix(Self.defaultRingCount).map(\.grapheme)
        var resolved: [GateGrapheme] = []
        resolved.reserveCapacity(ids.count)
        for id in ids {
            guard let entry = catalog.grapheme(named: id) else {
                throw WorldSeedError.invalidCombatDeflectGraphemes
            }
            resolved.append(entry)
        }
        graphemes = resolved
    }

    func validate() throws {
        guard monsterHP >= 1 else {
            throw WorldSeedError.invalidCombatMonsterHP(monsterHP)
        }
        guard orbTravelSeconds > 0 else {
            throw WorldSeedError.invalidCombatOrbTravelSeconds(orbTravelSeconds)
        }
        guard (Self.minRingCount...Self.maxRingCount).contains(graphemes.count) else {
            throw WorldSeedError.invalidCombatDeflectGraphemes
        }
        try CatalogValidators.validateGraphemeEntries(
            graphemes,
            requirePronunciation: false,
            emptyError: .invalidCombatDeflectGraphemes,
            invalidEntryError: .invalidCombatDeflectGraphemes
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
        // Both deflect YAML types share this case; the letter position picks the kind.
        case .deflect(let config):
            config.letterPosition == .ending ? .endingSoundDeflect : .startingSoundDeflect
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

    mutating func resolveGraphemes(from catalog: GraphemeCatalog) throws {
        for index in minigames.indices {
            if case .deflect(var config) = minigames[index] {
                try config.resolveGraphemes(from: catalog)
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
