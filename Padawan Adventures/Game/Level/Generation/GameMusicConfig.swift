import Foundation

/// Per-level minigame music track basenames (`Resources/Audio/Music/<name>.mp3`).
nonisolated struct GameMusicConfig: Codable, Equatable, Sendable {
    var combat: String?
    var pit: String?
    var gate: String?

    enum CodingKeys: String, CodingKey {
        case combat
        case pit
        case gate
    }

    nonisolated static let fallback = GameMusicConfig(
        combat: "combat",
        pit: "pit",
        gate: "gate"
    )

    nonisolated init(
        combat: String? = nil,
        pit: String? = nil,
        gate: String? = nil
    ) {
        self.combat = combat
        self.pit = pit
        self.gate = gate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        combat = try container.decodeIfPresent(String.self, forKey: .combat)
        pit = try container.decodeIfPresent(String.self, forKey: .pit)
        gate = try container.decodeIfPresent(String.self, forKey: .gate)
    }

    var combatCue: MusicCue { MusicCue.parse(combat) }
    var pitCue: MusicCue { MusicCue.parse(pit) }
    var gateCue: MusicCue { MusicCue.parse(gate) }
}
