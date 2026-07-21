import Foundation

struct GameEntity: Equatable, Sendable, Identifiable, WorldPersistable {
    var id: UUID
    var letter: Character
    var position: GridCoord
    var isPlayer: Bool

    init(id: UUID = UUID(), letter: Character, position: GridCoord, isPlayer: Bool = false) {
        self.id = id
        self.letter = letter
        self.position = position
        self.isPlayer = isPlayer
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case letter
        case position
        case isPlayer
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
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(String(letter), forKey: .letter)
        try container.encode(position, forKey: .position)
        try container.encode(isPlayer, forKey: .isPlayer)
    }
}
