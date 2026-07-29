import Foundation

/// The per-level baked art kinds. Each kind is one sheet + atlas pair inside the level folder.
nonisolated enum LevelAssetKind: String, CaseIterable, Sendable {
    case floor, letters, pit, gate, planet, treasure
}

/// Bundle locations for a level's baked art, keyed by the level's set name.
///
/// Set names double as level folder names (`1-tython`), so `floor.set` /
/// `letters.set` from the level YAML are what callers pass in.
nonisolated enum LevelAssetPaths {
    /// Bundle subdirectory holding one level's assets of a given kind.
    static func root(set name: String, _ kind: LevelAssetKind) -> String {
        switch kind {
        case .floor:    return "Sprites/Floor/\(name)"
        case .letters:  return "Sprites/Letters/\(name)"
        case .pit:      return "Sprites/Pit/\(name)"
        case .gate:     return "Sprites/Gate/Floor/\(name)"
        case .planet:   return "Sprites/UI/Levels"
        case .treasure: return "Sprites/Items/Treasure"
        }
    }

    /// Basename for a sheet or atlas, e.g. `1-tython-floor-atlas`.
    static func basename(set name: String, _ kind: LevelAssetKind, _ part: Part) -> String {
        "\(name)-\(kind.rawValue)-\(part.rawValue)"
    }

    enum Part: String, Sendable {
        case atlas
        case spritesheet
    }
}
