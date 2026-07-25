import Foundation
import Yams

/// Load settings for the floor spritesheet (`terrain.yaml` `sprite:` block).
nonisolated struct FloorSpriteConfig: Codable, Equatable, Sendable {
    /// Bundle subdirectory for the PNG (e.g. `Sprites/Floor`).
    var root: String
    var sheet: String
    /// Bundle subdirectory for the atlas JSON (e.g. `Sprites/Floor`).
    var atlasRoot: String
    var atlas: String
    var chromaKey: String?
    /// Per-channel chroma tolerance (0 = exact). Floor sheets use near-white, not pure `#FFFFFF`.
    var chromaKeyTolerance: UInt8
    /// Extra soft band beyond tolerance where alpha fades (kills white/black edge halos).
    var chromaKeyFeather: UInt8
    /// Box-blur radius (pixels) applied to the alpha matte after feathering.
    var chromaKeySmooth: Int

    enum CodingKeys: String, CodingKey {
        case root
        case sheet
        case atlasRoot = "atlas_root"
        case atlas
        case chromaKey = "chroma_key"
        case chromaKeyTolerance = "chroma_key_tolerance"
        case chromaKeyFeather = "chroma_key_feather"
        case chromaKeySmooth = "chroma_key_smooth"
    }

    init(
        root: String,
        sheet: String,
        atlasRoot: String,
        atlas: String,
        chromaKey: String? = nil,
        chromaKeyTolerance: UInt8 = 0,
        chromaKeyFeather: UInt8 = 0,
        chromaKeySmooth: Int = 0
    ) {
        self.root = root
        self.sheet = sheet
        self.atlasRoot = atlasRoot
        self.atlas = atlas
        self.chromaKey = chromaKey
        self.chromaKeyTolerance = chromaKeyTolerance
        self.chromaKeyFeather = chromaKeyFeather
        self.chromaKeySmooth = chromaKeySmooth
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        root = try container.decode(String.self, forKey: .root)
        sheet = try container.decode(String.self, forKey: .sheet)
        atlasRoot = try container.decode(String.self, forKey: .atlasRoot)
        atlas = try container.decode(String.self, forKey: .atlas)
        chromaKey = try container.decodeIfPresent(String.self, forKey: .chromaKey)
        let decodedTolerance = try container.decodeIfPresent(Int.self, forKey: .chromaKeyTolerance) ?? 0
        chromaKeyTolerance = UInt8(clamping: max(0, decodedTolerance))
        let decodedFeather = try container.decodeIfPresent(Int.self, forKey: .chromaKeyFeather) ?? 0
        chromaKeyFeather = UInt8(clamping: max(0, decodedFeather))
        chromaKeySmooth = max(0, try container.decodeIfPresent(Int.self, forKey: .chromaKeySmooth) ?? 0)
    }
}

/// One named terrain tile from `terrain.yaml`.
nonisolated struct TerrainDefinition: Codable, Equatable, Sendable {
    var row: Int
    var col: Int
    var nearby: [String]

    enum CodingKeys: String, CodingKey {
        case row
        case col
        case nearby
    }

    init(row: Int, col: Int, nearby: [String] = []) {
        self.row = row
        self.col = col
        self.nearby = nearby
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        row = try container.decode(Int.self, forKey: .row)
        col = try container.decode(Int.self, forKey: .col)
        nearby = try container.decodeIfPresent([String].self, forKey: .nearby) ?? []
    }
}

/// Decoded `terrain.yaml`: sprite load config + terrain id → definition.
nonisolated struct TerrainCatalog: Equatable, Sendable {
    var sprite: FloorSpriteConfig
    var terrains: [String: TerrainDefinition]

    /// Nearby affinity lists keyed by terrain id (for procedural assignment).
    var nearbyByID: [String: [String]] {
        terrains.mapValues(\.nearby)
    }

    static func loadFromBundle(
        named name: String = "terrain",
        withExtension ext: String = "yaml",
        bundle: Bundle = .main
    ) throws -> TerrainCatalog {
        guard let url = bundle.url(forResource: name, withExtension: ext) else {
            throw TerrainCatalogError.missingResource("\(name).\(ext)")
        }
        return try decode(from: Data(contentsOf: url))
    }

    static func decode(from data: Data) throws -> TerrainCatalog {
        let decoder = YAMLDecoder()
        let doc: Document
        do {
            doc = try decoder.decode(Document.self, from: data)
        } catch {
            throw TerrainCatalogError.decodeFailed(String(describing: error))
        }
        guard !doc.terrains.isEmpty else {
            throw TerrainCatalogError.emptyTerrains
        }
        return TerrainCatalog(sprite: doc.sprite, terrains: doc.terrains)
    }

    private struct Document: Decodable {
        var sprite: FloorSpriteConfig
        var terrains: [String: TerrainDefinition]
    }
}

enum TerrainCatalogError: Error, Equatable {
    case missingResource(String)
    case decodeFailed(String)
    case emptyTerrains
}
