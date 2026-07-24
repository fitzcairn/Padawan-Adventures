import Foundation

/// Shared sprite definition used by player, enemies, UI, and other visual elements.
nonisolated struct SpriteConfig: Codable, Equatable, Sendable {
    /// Bundle subdirectory prefix for sheet/atlas basenames (e.g. `Sprites/Player`).
    var root: String
    /// Hex RGB color removed from sheets when slicing frames (e.g. `#000000`).
    var chromaKey: String?
    /// Scales displayed height (`wall_height` × multiplier); width follows texture aspect.
    var sizeMultiplier: Double
    /// Percent of scaled sprite height; shifts the sprite toward the bottom of the screen.
    var anchorCorrection: Double
    /// Animation name → sheet source or horizontal flip of another animation.
    var animations: [String: SpriteAnimationSource]

    enum CodingKeys: String, CodingKey {
        case root
        case chromaKey = "chroma_key"
        case sizeMultiplier = "size_multiplier"
        case anchorCorrection = "anchor_correction"
        case animations
    }

    init(
        root: String,
        chromaKey: String? = nil,
        sizeMultiplier: Double = 1,
        anchorCorrection: Double = 0,
        animations: [String: SpriteAnimationSource] = [:]
    ) {
        self.root = root
        self.chromaKey = chromaKey
        self.sizeMultiplier = sizeMultiplier
        self.anchorCorrection = anchorCorrection
        self.animations = animations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        root = try container.decode(String.self, forKey: .root)
        chromaKey = try container.decodeIfPresent(String.self, forKey: .chromaKey)
        sizeMultiplier = try container.decodeIfPresent(Double.self, forKey: .sizeMultiplier) ?? 1
        anchorCorrection = try container.decodeIfPresent(Double.self, forKey: .anchorCorrection) ?? 0
        animations = try container.decodeIfPresent([String: SpriteAnimationSource].self, forKey: .animations) ?? [:]
    }
}

/// Either a spritesheet + atlas pair, or a horizontal flip of another named animation.
nonisolated enum SpriteAnimationSource: Codable, Equatable, Sendable {
    case sheet(sheet: String, atlas: String)
    case flipOf(String)

    enum CodingKeys: String, CodingKey {
        case sheet
        case atlas
        case flipOf = "flip_of"
    }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let basename = try? single.decode(String.self) {
            self = .sheet(sheet: basename, atlas: basename)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let flipOf = try container.decodeIfPresent(String.self, forKey: .flipOf) {
            self = .flipOf(flipOf)
            return
        }

        let sheet = try container.decode(String.self, forKey: .sheet)
        let atlas = try container.decodeIfPresent(String.self, forKey: .atlas) ?? sheet
        self = .sheet(sheet: sheet, atlas: atlas)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .sheet(let sheet, let atlas):
            try container.encode(sheet, forKey: .sheet)
            try container.encode(atlas, forKey: .atlas)
        case .flipOf(let name):
            try container.encode(name, forKey: .flipOf)
        }
    }
}
