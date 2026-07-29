import CoreGraphics
import Foundation

/// Per-level baked world gate wall atlas (Sendable — safe across `Task.detached`).
///
/// Loaded from `Levels/{set}/{set}-gate-atlas.json`.
/// Frames are `along_x` / `along_y` for 2-tile gate strips on each iso axis.
nonisolated struct GateSpriteSet: Codable, Equatable, Sendable {
    struct Anchor: Codable, Equatable, Sendable {
        var x: CGFloat
        var y: CGFloat
    }

    struct Meta: Codable, Equatable, Sendable {
        var version: Int
        var gateSet: String
        var size: Size
        var frameCount: Int?
        var footprintTiles: Int?
        var footprintScreenWidths: CGFloat?

        struct Size: Codable, Equatable, Sendable {
            var w: Int
            var h: Int
        }

        enum CodingKeys: String, CodingKey {
            case version
            case size
            case gateSet = "gate_set"
            case frameCount = "frame_count"
            case footprintTiles = "footprint_tiles"
            case footprintScreenWidths = "footprint_screen_widths"
        }
    }

    struct Frame: Codable, Equatable, Sendable {
        var x: Int
        var y: Int
        var w: Int
        var h: Int
        var anchor: Anchor?
        var baseW: CGFloat?

        enum CodingKeys: String, CodingKey {
            case x, y, w, h
            case anchor
            case baseW = "base_w"
        }
    }

    /// Strip axis for a contiguous 2-tile gate.
    enum Axis: String, Codable, CaseIterable, Sendable {
        case alongX = "along_x"
        case alongY = "along_y"
    }

    var meta: Meta
    var frames: [String: Frame]

    var axisIDs: [String] {
        Axis.allCases.map(\.rawValue).filter { frames[$0] != nil }
    }

    func frame(for axis: Axis) -> Frame? {
        frames[axis.rawValue]
    }

    /// Screen-space width factor relative to `tileWidth` for a 2-tile iso strip bbox.
    var footprintScreenWidths: CGFloat {
        meta.footprintScreenWidths ?? 1.5
    }

    static func loadFromBundle(set name: String, bundle: Bundle = .main) throws -> GateSpriteSet {
        let atlasName = LevelAssetPaths.basename(set: name, .gate, .atlas)
        let root = LevelAssetPaths.root(set: name, .gate)
        let url = try SpriteSheetLoader.resourceURL(
            named: atlasName,
            extensions: ["json"],
            root: root,
            bundle: bundle
        )
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(GateSpriteSet.self, from: data)
    }
}

enum GateSpriteSetError: Error, Equatable {
    case missingSet(String)
    case emptySet(String)
}
