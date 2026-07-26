import CoreGraphics
import Foundation

/// TexturePacker-style atlas describing frames inside a spritesheet PNG.
///
/// Also decodes floor atlases: named string keys (e.g. `"sand"`) with optional
/// per-frame `anchor` blocks. Character sheets keep numeric keys (`"0"`, `"1"`, …).
nonisolated struct SpriteAtlas: Codable, Equatable, Sendable {
    var frames: [String: SpriteAtlasFrame]
    var meta: SpriteAtlasMeta

    struct SpriteAtlasFrame: Codable, Equatable, Sendable {
        var x: Int
        var y: Int
        var w: Int
        var h: Int
        /// Relative duration weight (often `1`); scaled against `meta.duration_s`.
        var duration: Double?
        /// Optional diamond / ground-contact anchor (floor terrains).
        var anchor: FloorAnchor?
    }

    struct SpriteAtlasMeta: Codable, Equatable, Sendable {
        var size: Size?
        var frameSize: Size?
        var backgroundMode: String?
        var durationS: Double?

        enum CodingKeys: String, CodingKey {
            case size
            case frameSize = "frame_size"
            case backgroundMode = "background_mode"
            case durationS = "duration_s"
        }

        struct Size: Codable, Equatable, Sendable {
            var w: Int
            var h: Int
        }
    }

    /// Frames ordered by numeric key (`"0"`, `"1"`, …).
    var orderedFrames: [(key: String, frame: SpriteAtlasFrame)] {
        frames
            .compactMap { key, frame -> (Int, String, SpriteAtlasFrame)? in
                guard let index = Int(key) else { return nil }
                return (index, key, frame)
            }
            .sorted { $0.0 < $1.0 }
            .map { ($0.1, $0.2) }
    }

    /// Pixel rect for a named frame (image top-left origin). Used by floor terrains.
    func frameRect(named id: String) -> CGRect? {
        guard let frame = frames[id], frame.w > 0, frame.h > 0 else { return nil }
        return CGRect(x: frame.x, y: frame.y, width: frame.w, height: frame.h)
    }

    /// Fallback FPS when atlas `meta.duration_s` is missing.
    static let fallbackFramesPerSecond: Double = 12

    /// Per-frame durations in seconds.
    ///
    /// When `meta.duration_s` is set, frame `duration` values are relative weights
    /// scaled so the full loop lasts `duration_s` seconds.
    func frameDurationsSeconds() -> [TimeInterval] {
        frameDurationsSeconds(ordered: orderedFrames.map(\.frame))
    }

    func frameDurationsSeconds(ordered: [SpriteAtlasFrame]) -> [TimeInterval] {
        guard !ordered.isEmpty else { return [] }
        let weights = ordered.map { max($0.duration ?? 1, 0.000_001) }
        let weightSum = weights.reduce(0, +)
        if let total = meta.durationS, total > 0 {
            return weights.map { total * ($0 / weightSum) }
        }
        return Array(repeating: 1.0 / Self.fallbackFramesPerSecond, count: ordered.count)
    }

    static func decode(from data: Data) throws -> SpriteAtlas {
        try JSONDecoder().decode(SpriteAtlas.self, from: data)
    }
}
