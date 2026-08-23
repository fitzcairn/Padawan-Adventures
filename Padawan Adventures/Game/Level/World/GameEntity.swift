import Foundation

nonisolated enum PickupKind: String, Codable, Equatable, Sendable, CaseIterable {
    case health
    case energy
    case treasure
}

nonisolated struct GameEntity: Equatable, Sendable, Identifiable, WorldPersistable {
    var id: UUID
    var letter: Character
    var position: GridCoord
    var isPlayer: Bool
    /// Named enemy type from `combat.yaml`; nil for the player.
    var enemyTypeID: String?
    /// Pickup type when this entity is a collectible; nil otherwise.
    var pickupKind: PickupKind?
    /// NPC catalog id (`npcs.yaml` sprites key); nil for player / enemy / pickup.
    var npcID: String?
    /// Pinned at generation (and in demo mode); nil means roll from weights (legacy saves).
    var combatMinigame: CombatMinigameKind?

    init(
        id: UUID = UUID(),
        letter: Character,
        position: GridCoord,
        isPlayer: Bool = false,
        enemyTypeID: String? = nil,
        pickupKind: PickupKind? = nil,
        npcID: String? = nil,
        combatMinigame: CombatMinigameKind? = nil
    ) {
        self.id = id
        self.letter = letter
        self.position = position
        self.isPlayer = isPlayer
        self.enemyTypeID = enemyTypeID
        self.pickupKind = pickupKind
        self.npcID = npcID
        self.combatMinigame = combatMinigame
    }

    var isEnemy: Bool { enemyTypeID != nil && !isPlayer }
    var isPickup: Bool { pickupKind != nil && !isPlayer }
    var isMerchant: Bool { npcID == "merchant" && !isPlayer }

    private enum CodingKeys: String, CodingKey {
        case id
        case letter
        case position
        case isPlayer
        case enemyTypeID
        case pickupKind
        case npcID
        case combatMinigame
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        let letterString = try container.decode(String.self, forKey: .letter)
        guard let first = letterString.first else {
            throw GameSaveError.invalidEntityLetter
        }
        letter = first
        position = try container.decode(GridCoord.self, forKey: .position)
        isPlayer = try container.decode(Bool.self, forKey: .isPlayer)
        enemyTypeID = try container.decodeIfPresent(String.self, forKey: .enemyTypeID)
        pickupKind = try container.decodeIfPresent(PickupKind.self, forKey: .pickupKind)
        npcID = try container.decodeIfPresent(String.self, forKey: .npcID)
        combatMinigame = try container.decodeIfPresent(CombatMinigameKind.self, forKey: .combatMinigame)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(String(letter), forKey: .letter)
        try container.encode(position, forKey: .position)
        try container.encode(isPlayer, forKey: .isPlayer)
        try container.encodeIfPresent(enemyTypeID, forKey: .enemyTypeID)
        try container.encodeIfPresent(pickupKind, forKey: .pickupKind)
        try container.encodeIfPresent(npcID, forKey: .npcID)
        try container.encodeIfPresent(combatMinigame, forKey: .combatMinigame)
    }
}
