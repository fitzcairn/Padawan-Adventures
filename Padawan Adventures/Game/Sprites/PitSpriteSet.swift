import CoreGraphics
import Foundation

/// Per-level baked pit platform tile atlas (Sendable — safe across `Task.detached`).
///
/// Loaded from `Levels/{set}/{set}-pit-atlas.json`.
nonisolated struct PitSpriteSet: Codable, Equatable, Sendable {
    struct Meta: Codable, Equatable, Sendable {
        var version: Int
        var pitSet: String
        var size: Size
        var tileCount: Int?

        struct Size: Codable, Equatable, Sendable {
            var w: Int
            var h: Int
        }

        enum CodingKeys: String, CodingKey {
            case version
            case size
            case pitSet = "pit_set"
            case tileCount = "tile_count"
        }
    }

    struct Frame: Codable, Equatable, Sendable {
        var x: Int
        var y: Int
        var w: Int
        var h: Int
    }

    var meta: Meta
    var frames: [String: Frame]

    /// Sorted numeric frame keys (`"0"`, `"1"`, …).
    var tileIDs: [String] {
        frames.keys.sorted { lhs, rhs in
            (Int(lhs) ?? 0) < (Int(rhs) ?? 0)
        }
    }

    static func loadFromBundle(set name: String, bundle: Bundle = .main) throws -> PitSpriteSet {
        let atlasName = LevelAssetPaths.basename(set: name, .pit, .atlas)
        let root = LevelAssetPaths.root(set: name, .pit)
        let url = try SpriteSheetLoader.resourceURL(
            named: atlasName,
            extensions: ["json"],
            root: root,
            bundle: bundle
        )
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(PitSpriteSet.self, from: data)
    }
}

enum PitSpriteSetError: Error, Equatable {
    case missingSet(String)
    case emptySet(String)
}
