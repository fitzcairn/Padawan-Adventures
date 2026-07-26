import Foundation
import UIKit

/// Optional decorative particle halo drawn behind a sprite (`highlight:` in YAML).
///
/// All sizes are fractions of the sprite's display height so one block works for
/// any item scale. Shared config type — not item-specific; any sprite config can
/// adopt it later.
nonisolated struct HighlightConfig: Codable, Equatable, Sendable {
    /// Particle tint, `#RGB`, `#RRGGBB`, or `#RRGGBBAA`.
    var color: String
    /// Particles spawned per second.
    var birthRate: Double
    /// Seconds a particle lives before it is fully faded.
    var lifetime: Double
    /// Horizontal spawn spread as a fraction of sprite height. Vertical spread is
    /// squashed to 60% of this so the pool reads as an isometric ellipse.
    var radius: Double
    /// Particle diameter as a fraction of sprite height.
    var particleSize: Double
    /// Peak particle alpha.
    var alpha: Double
    /// Emitter centre above the tile, as a fraction of sprite height.
    var yOffset: Double

    enum CodingKeys: String, CodingKey {
        case color
        case birthRate = "birth_rate"
        case lifetime
        case radius
        case particleSize = "particle_size"
        case alpha
        case yOffset = "y_offset"
    }

    init(
        color: String = "#FFD54F",
        birthRate: Double = 22,
        lifetime: Double = 1.1,
        radius: Double = 0.45,
        particleSize: Double = 0.12,
        alpha: Double = 0.85,
        yOffset: Double = 0.45
    ) {
        self.color = color
        self.birthRate = birthRate
        self.lifetime = lifetime
        self.radius = radius
        self.particleSize = particleSize
        self.alpha = alpha
        self.yOffset = yOffset
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        color = try container.decodeIfPresent(String.self, forKey: .color) ?? "#FFD54F"
        birthRate = try container.decodeIfPresent(Double.self, forKey: .birthRate) ?? 22
        lifetime = try container.decodeIfPresent(Double.self, forKey: .lifetime) ?? 1.1
        radius = try container.decodeIfPresent(Double.self, forKey: .radius) ?? 0.45
        particleSize = try container.decodeIfPresent(Double.self, forKey: .particleSize) ?? 0.12
        alpha = try container.decodeIfPresent(Double.self, forKey: .alpha) ?? 0.85
        yOffset = try container.decodeIfPresent(Double.self, forKey: .yOffset) ?? 0.45
    }

    /// Parsed tint, or a fallback yellow when the hex string is malformed.
    var uiColor: UIColor { UIColor(hex: color) ?? .systemYellow }
}
