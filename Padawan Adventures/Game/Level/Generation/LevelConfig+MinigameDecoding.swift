import Foundation

// MARK: - GateConfig Decodable (private DTO)

extension GateConfig {
    /// Decodes the `gate:` keyed block or falls back to `.fallback`.
    nonisolated init(
        from decoder: Decoder,
        container: KeyedDecodingContainer<LevelConfig.CodingKeys>
    ) throws {
        guard container.contains(.gate) else {
            self = .fallback
            return
        }
        let dto = try container.decode(GateConfigDTO.self, forKey: .gate)
        fx = dto.fx ?? SoundEffectTable(events: ["opened": "gate-open"])
        music = dto.music
        minigameChance = dto.minigameChance ?? 0.6
        guard let entries = dto.minigames, !entries.isEmpty else {
            throw WorldSeedError.decodeFailed("gate.minigames must not be empty")
        }
        minigames = try entries.map { try MinigameDecodeRegistry.decodeGateMinigame(from: $0) }
    }
}

private nonisolated struct GateConfigDTO: Decodable {
    var fx: SoundEffectTable?
    var music: String?
    var minigameChance: Double?
    var minigames: [GateMinigameDTO]?

    enum CodingKeys: String, CodingKey {
        case fx
        case music
        case minigameChance = "minigame_probability"
        case minigames
    }
}

// MARK: - CombatConfig Decodable (private DTO)

extension CombatConfig {
    /// Decodes the `combat:` keyed block or falls back to slash-only.
    nonisolated init(
        from decoder: Decoder,
        container: KeyedDecodingContainer<LevelConfig.CodingKeys>
    ) throws {
        guard container.contains(.combat) else {
            self = .fallback
            return
        }
        let dto = try container.decode(CombatConfigDTO.self, forKey: .combat)
        music = dto.music
        guard let entries = dto.minigames, !entries.isEmpty else {
            throw WorldSeedError.decodeFailed("combat.minigames must not be empty")
        }
        minigames = try entries.map { try MinigameDecodeRegistry.decodeCombatMinigame(from: $0) }
    }
}

private nonisolated struct CombatConfigDTO: Decodable {
    var music: String?
    var minigames: [CombatMinigameDTO]?
}

// MARK: - PitConfig Decodable (private DTO)

extension PitConfig {
    /// Decodes the `pit:` keyed block or falls back to sound-out-word only.
    nonisolated init(
        from decoder: Decoder,
        container: KeyedDecodingContainer<LevelConfig.CodingKeys>
    ) throws {
        guard container.contains(.pit) else {
            self = .fallback
            return
        }
        let dto = try container.decode(PitConfigDTO.self, forKey: .pit)
        fx = dto.fx ?? Self.fallback.fx
        music = dto.music
        guard let entries = dto.minigames, !entries.isEmpty else {
            throw WorldSeedError.decodeFailed("pit.minigames must not be empty")
        }
        minigames = try entries.map { try MinigameDecodeRegistry.decodePitMinigame(from: $0) }
    }
}

private nonisolated struct PitConfigDTO: Decodable {
    var fx: SoundEffectTable?
    var music: String?
    var minigames: [PitMinigameDTO]?
}
