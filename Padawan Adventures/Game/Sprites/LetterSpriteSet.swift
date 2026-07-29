import CoreGraphics
import Foundation

/// Per-level baked letter glyph atlas (Sendable — safe across `Task.detached`).
///
/// Loaded from `Sprites/Letters/{set}/Baked/{set}-letters-atlas.json`.
nonisolated struct LetterSpriteSet: Codable, Equatable, Sendable {
    struct Meta: Codable, Equatable, Sendable {
        var version: Int
        var letterSet: String
        var size: Size
        var glyphCount: Int?

        struct Size: Codable, Equatable, Sendable {
            var w: Int
            var h: Int
        }

        enum CodingKeys: String, CodingKey {
            case version
            case size
            case letterSet = "letter_set"
            case glyphCount = "glyph_count"
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

    /// All expected glyph keys: `A`…`Z` then `a`…`z`.
    static let expectedKeys: [String] =
        Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init)
        + Array("abcdefghijklmnopqrstuvwxyz").map(String.init)

    var missingKeys: [String] {
        Self.expectedKeys.filter { frames[$0] == nil }
    }

    static func loadFromBundle(set name: String, bundle: Bundle = .main) throws -> LetterSpriteSet {
        let atlasName = LevelAssetPaths.basename(set: name, .letters, .atlas)
        let root = LevelAssetPaths.root(set: name, .letters)
        let url = try SpriteSheetLoader.resourceURL(
            named: atlasName,
            extensions: ["json"],
            root: root,
            bundle: bundle
        )
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(LetterSpriteSet.self, from: data)
    }
}

enum LetterSpriteSetError: Error, Equatable {
    case missingSet(String)
    case incompleteGlyphs(String, missing: [String])
}
