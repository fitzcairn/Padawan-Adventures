import Foundation

/// Shared sprite definition used by player, enemies, UI, and other visual elements.
nonisolated struct SpriteConfig: Codable, Equatable, Sendable {
    /// Bundle-relative subdirectory for sheet/atlas basenames.
    ///
    /// With `Resources/Sprites` in the Xcode project's `explicitFolders`, paths
    /// keep the on-disk tree (e.g. `Sprites/Player`, `Sprites/Enemies/Dino`).
    /// Enemy YAML may still say `Enemies/<Type>`; the loader also tries
    /// `Sprites/Enemies/<Type>`.
    var root: String
    /// Hex RGB color removed from sheets when slicing frames (e.g. `#000000`).
    var chromaKey: String?
    /// Per-channel chroma tolerance (0 = exact). Near-white sheets often need a small fuzz.
    var chromaKeyTolerance: UInt8
    /// Extra soft band beyond tolerance where alpha fades (kills key-color edge halos).
    var chromaKeyFeather: UInt8
    /// Box-blur radius (pixels) applied to the alpha matte after feathering.
    var chromaKeySmooth: Int
    /// Display height as a fraction of wall height (`wall_height` × `scale`); width follows texture aspect.
    var scale: Double
    /// Percent of scaled sprite height; shifts the sprite toward the bottom of the screen.
    var anchorCorrection: Double
    /// Animation name → sheet source or horizontal flip of another animation.
    var animations: [String: SpriteAnimationSource]
    /// When false, keeps atlas frame rects as-is instead of cropping to shared opaque bounds.
    var trim: Bool

    enum CodingKeys: String, CodingKey {
        case root
        case chroma
        case chromaKey = "chroma_key"
        case chromaKeyTolerance = "chroma_key_tolerance"
        case chromaKeyFeather = "chroma_key_feather"
        case chromaKeySmooth = "chroma_key_smooth"
        case scale
        case anchorCorrection = "anchor_correction"
        case animations
        case trim
    }

    /// Named chroma presets for YAML `chroma:` (explicit `chroma_key*` still override).
    nonisolated static let chromaPresets: [String: (
        key: String,
        tolerance: UInt8,
        feather: UInt8,
        smooth: Int
    )] = [
        "black": ("#000000", 0, 0, 0),
        "black_soft": ("#000000", 2, 0, 0),
        "white_soft": ("#FFFFFF", 18, 48, 2),
        "white_item": ("#FFFFFF", 12, 20, 2),
    ]

    init(
        root: String,
        chromaKey: String? = nil,
        chromaKeyTolerance: UInt8 = 0,
        chromaKeyFeather: UInt8 = 0,
        chromaKeySmooth: Int = 0,
        scale: Double = 1,
        anchorCorrection: Double = 0,
        animations: [String: SpriteAnimationSource] = [:],
        trim: Bool = true
    ) {
        self.root = root
        self.chromaKey = chromaKey
        self.chromaKeyTolerance = chromaKeyTolerance
        self.chromaKeyFeather = chromaKeyFeather
        self.chromaKeySmooth = chromaKeySmooth
        self.scale = scale
        self.anchorCorrection = anchorCorrection
        self.animations = animations
        self.trim = trim
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        root = try container.decode(String.self, forKey: .root)

        var key: String?
        var tolerance: UInt8 = 0
        var feather: UInt8 = 0
        var smooth = 0

        if let presetName = try container.decodeIfPresent(String.self, forKey: .chroma)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !presetName.isEmpty,
           let preset = Self.chromaPresets[presetName] {
            key = preset.key
            tolerance = preset.tolerance
            feather = preset.feather
            smooth = preset.smooth
        }

        if let explicit = try container.decodeIfPresent(String.self, forKey: .chromaKey) {
            key = explicit
        }
        if let decodedTolerance = try container.decodeIfPresent(Int.self, forKey: .chromaKeyTolerance) {
            tolerance = UInt8(clamping: max(0, decodedTolerance))
        }
        if let decodedFeather = try container.decodeIfPresent(Int.self, forKey: .chromaKeyFeather) {
            feather = UInt8(clamping: max(0, decodedFeather))
        }
        if let decodedSmooth = try container.decodeIfPresent(Int.self, forKey: .chromaKeySmooth) {
            smooth = max(0, decodedSmooth)
        }

        chromaKey = key
        chromaKeyTolerance = tolerance
        chromaKeyFeather = feather
        chromaKeySmooth = smooth
        scale = try container.decodeIfPresent(Double.self, forKey: .scale) ?? 1
        anchorCorrection = try container.decodeIfPresent(Double.self, forKey: .anchorCorrection) ?? 0
        animations = try container.decodeIfPresent([String: SpriteAnimationSource].self, forKey: .animations) ?? [:]
        trim = try container.decodeIfPresent(Bool.self, forKey: .trim) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(root, forKey: .root)
        try container.encodeIfPresent(chromaKey, forKey: .chromaKey)
        try container.encode(Int(chromaKeyTolerance), forKey: .chromaKeyTolerance)
        try container.encode(Int(chromaKeyFeather), forKey: .chromaKeyFeather)
        try container.encode(chromaKeySmooth, forKey: .chromaKeySmooth)
        try container.encode(scale, forKey: .scale)
        try container.encode(anchorCorrection, forKey: .anchorCorrection)
        try container.encode(animations, forKey: .animations)
        try container.encode(trim, forKey: .trim)
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
