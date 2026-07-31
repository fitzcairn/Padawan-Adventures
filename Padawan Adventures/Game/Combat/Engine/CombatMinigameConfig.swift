import Foundation

/// Discriminator for which combat minigame an encounter runs. Raw values match YAML `type:`.
nonisolated enum CombatMinigameKind: String, Codable, Equatable, Sendable, CaseIterable {
    /// The original swipe-to-slash arena (`CombatScene`).
    case slash
    /// Tap-the-matching-ring deflect arena (`CombatDeflectScene`).
    case deflect
}

/// Per-entry config for the slash arena. Its gameplay knobs still come from
/// `enemies.yaml` + the level's `combat_letter_*` keys; only the pick weight lives here.
nonisolated struct CombatSlashConfig: Equatable, Sendable {
    var weight: Double

    nonisolated static let fallback = CombatSlashConfig(weight: 1)

    nonisolated init(weight: Double = 1) {
        self.weight = weight
    }
}

/// Per-entry config for the deflect arena.
nonisolated struct CombatDeflectConfig: Equatable, Sendable {
    var weight: Double
    /// Monster hit points; also the star award on win.
    var monsterHP: Int
    /// Seconds for an orb to fly from the monster to the player.
    var orbTravelSeconds: Double
    /// Optional subset of shared catalog ids (`nil` = first `ringCount` catalog entries).
    /// Order is meaningful: left to right on screen (northwest, up, northeast).
    var letterIDs: [String]?
    /// Resolved letters in `letterIDs` order. Populated via `resolveLetters(from:)`.
    var letters: [GateLetter]

    static let defaultMonsterHP = 5
    static let defaultOrbTravelSeconds: Double = 3
    /// Exactly three rings are drawn, so exactly three letters are used.
    static let ringCount = 3

    nonisolated static let fallback = CombatDeflectConfig(
        weight: 1,
        letterIDs: ["a", "b", "c"],
        letters: Array(LetterCatalog.fallback.letters.prefix(ringCount))
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
        let ids = letterIDs ?? catalog.letters.prefix(Self.ringCount).map(\.letter)
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
        guard letters.count == Self.ringCount else {
            throw WorldSeedError.invalidCombatDeflectLetters
        }
        let letterSet = CharacterSet.letters
        var seen = Set<String>()
        for entry in letters {
            guard entry.letter.count == 1,
                  entry.letter.unicodeScalars.allSatisfy({ letterSet.contains($0) }),
                  !entry.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  seen.insert(entry.letter).inserted else {
                throw WorldSeedError.invalidCombatDeflectLetters
            }
        }
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
    var minigames: [CombatMinigameConfig]

    /// Used when a level omits `combat:` entirely — slash only, preserving old behaviour.
    nonisolated static let fallback = CombatConfig(minigames: [.slash(.fallback)])

    nonisolated init(minigames: [CombatMinigameConfig]) {
        self.minigames = minigames
    }

    func minigame(for kind: CombatMinigameKind) -> CombatMinigameConfig? {
        minigames.first { $0.kind == kind }
    }

    /// Weighted pick. Entries with weight 0 are never chosen unless every weight is 0,
    /// in which case the first entry wins so an encounter always has something to run.
    func pickMinigame(using rng: inout some RandomNumberGenerator) -> CombatMinigameConfig {
        precondition(!minigames.isEmpty, "CombatConfig.minigames must not be empty")
        let total = minigames.reduce(0.0) { $0 + max($1.weight, 0) }
        guard total > 0 else { return minigames[0] }
        var roll = Double.random(in: 0..<total, using: &rng)
        for entry in minigames {
            roll -= max(entry.weight, 0)
            if roll < 0 { return entry }
        }
        return minigames[minigames.count - 1]
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
            if case .deflect(let config) = entry { try config.validate() }
        }
    }
}
