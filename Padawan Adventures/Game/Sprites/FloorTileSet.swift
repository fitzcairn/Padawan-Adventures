import CoreGraphics
import Foundation

/// Per-level baked floor tile atlas (Sendable — safe across `Task.detached`).
///
/// Loaded from `Sprites/Floor/{set}/Baked/{set}-floor-atlas.json`.
nonisolated struct FloorTileSet: Codable, Equatable, Sendable {
    enum Side: String, Codable, CaseIterable, Sendable {
        case ne = "NE"
        case se = "SE"
        case sw = "SW"
        case nw = "NW"
    }

    enum Role: String, Codable, Sendable {
        case floor
        case pit
        case decor
    }

    struct Anchor: Codable, Equatable, Sendable {
        var x: CGFloat
        var y: CGFloat
    }

    struct Diamond: Codable, Equatable, Sendable {
        var w: CGFloat
        var h: CGFloat
        var wallDepth: CGFloat

        enum CodingKeys: String, CodingKey {
            case w
            case h
            case wallDepth = "wall_depth"
        }
    }

    struct Grid: Codable, Equatable, Sendable {
        var cols: Int
        var rows: Int
        var cellW: CGFloat
        var cellH: CGFloat

        enum CodingKeys: String, CodingKey {
            case cols
            case rows
            case cellW = "cell_w"
            case cellH = "cell_h"
        }
    }

    struct Material: Codable, Equatable, Sendable {
        var rgb: [Int]
        var kind: String
        var hint: String?
    }

    struct Meta: Codable, Equatable, Sendable {
        var version: Int
        var floorSet: String
        var size: Size
        var grid: Grid
        var diamond: Diamond
        var materials: [String: Material]
        var edgeOrder: [String]
        var confidentTiles: Int?
        /// `"sheet"` when roles came from `*-floor-spritesheet-pit.png`, else `"heuristic"`.
        var pitSource: String?

        struct Size: Codable, Equatable, Sendable {
            var w: Int
            var h: Int
        }

        enum CodingKeys: String, CodingKey {
            case version
            case floorSet = "floor_set"
            case size
            case grid
            case diamond
            case materials
            case edgeOrder = "edge_order"
            case confidentTiles = "confident_tiles"
            case pitSource = "pit_source"
        }
    }

    struct Frame: Codable, Equatable, Sendable {
        var x: Int
        var y: Int
        var w: Int
        var h: Int
        var anchor: Anchor
        var role: Role
        var weight: Double
        var edges: [String: String]
        var matches: [String: [String]]
        var cell: [Int]?

        enum CodingKeys: String, CodingKey {
            case x, y, w, h
            case anchor
            case role
            case weight
            case edges
            case matches
            case cell
        }

        init(
            x: Int,
            y: Int,
            w: Int,
            h: Int,
            anchor: Anchor,
            role: Role,
            weight: Double = 1,
            edges: [String: String] = [:],
            matches: [String: [String]] = [:],
            cell: [Int]? = nil
        ) {
            self.x = x
            self.y = y
            self.w = w
            self.h = h
            self.anchor = anchor
            self.role = role
            self.weight = weight
            self.edges = edges
            self.matches = matches
            self.cell = cell
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            x = try c.decode(Int.self, forKey: .x)
            y = try c.decode(Int.self, forKey: .y)
            w = try c.decode(Int.self, forKey: .w)
            h = try c.decode(Int.self, forKey: .h)
            anchor = try c.decode(Anchor.self, forKey: .anchor)
            role = try c.decode(Role.self, forKey: .role)
            weight = try c.decodeIfPresent(Double.self, forKey: .weight) ?? 1
            edges = try c.decodeIfPresent([String: String].self, forKey: .edges) ?? [:]
            matches = try c.decodeIfPresent([String: [String]].self, forKey: .matches) ?? [:]
            cell = try c.decodeIfPresent([Int].self, forKey: .cell)
        }
    }

    struct PitEntry: Codable, Equatable, Sendable {
        var voidMask: [String]
        var kind: String

        enum CodingKeys: String, CodingKey {
            case voidMask = "void_mask"
            case kind
        }
    }

    struct Pits: Codable, Equatable, Sendable {
        var tiles: [String: PitEntry]
        var byMask: [String: [String]]

        enum CodingKeys: String, CodingKey {
            case tiles
            case byMask = "by_mask"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            tiles = try c.decodeIfPresent([String: PitEntry].self, forKey: .tiles) ?? [:]
            byMask = try c.decodeIfPresent([String: [String]].self, forKey: .byMask) ?? [:]
        }

        init(tiles: [String: PitEntry] = [:], byMask: [String: [String]] = [:]) {
            self.tiles = tiles
            self.byMask = byMask
        }
    }

    var meta: Meta
    var frames: [String: Frame]
    var pits: Pits

    enum CodingKeys: String, CodingKey {
        case meta
        case frames
        case pits
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        meta = try c.decode(Meta.self, forKey: .meta)
        frames = try c.decode([String: Frame].self, forKey: .frames)
        pits = try c.decodeIfPresent(Pits.self, forKey: .pits) ?? Pits()
    }

    init(meta: Meta, frames: [String: Frame], pits: Pits = Pits()) {
        self.meta = meta
        self.frames = frames
        self.pits = pits
    }

    /// `NE <-> SW`, `SE <-> NW`.
    static func opposite(_ side: Side) -> Side {
        switch side {
        case .ne: return .sw
        case .se: return .nw
        case .sw: return .ne
        case .nw: return .se
        }
    }

    /// Grid delta a side faces.
    static func delta(_ side: Side) -> (dx: Int, dy: Int) {
        switch side {
        case .ne: return (0, -1)
        case .se: return (1, 0)
        case .sw: return (0, 1)
        case .nw: return (-1, 0)
        }
    }

    var floorTileIDs: [String] {
        frames.filter { $0.value.role == .floor }.map(\.key).sorted()
    }

    var decorTileIDs: [String] {
        frames.filter { $0.value.role == .decor }.map(\.key).sorted()
    }

    var pitTileIDs: [String] {
        frames.filter { $0.value.role == .pit }.map(\.key).sorted()
    }

    /// Exact void-mask match, else best Jaccard overlap, else any pit tile.
    func pitTiles(matching mask: Set<Side>) -> [String] {
        let key = mask.map(\.rawValue).sorted().joined(separator: ",")
        if let exact = pits.byMask[key], !exact.isEmpty {
            return exact.filter { frames[$0]?.role == .pit }
        }

        var bestScore: Double = -1
        var best: [String] = []
        for (tid, entry) in pits.tiles {
            guard frames[tid]?.role == .pit else { continue }
            let entrySet = Set(entry.voidMask.compactMap(Side.init(rawValue:)))
            let inter = Double(mask.intersection(entrySet).count)
            let union = Double(mask.union(entrySet).count)
            let score = union > 0 ? inter / union : (mask.isEmpty && entrySet.isEmpty ? 1 : 0)
            if score > bestScore {
                bestScore = score
                best = [tid]
            } else if score == bestScore {
                best.append(tid)
            }
        }
        if !best.isEmpty { return best.sorted() }
        return pitTileIDs
    }

    static func loadFromBundle(set name: String, bundle: Bundle = .main) throws -> FloorTileSet {
        let atlasName = LevelAssetPaths.basename(set: name, .floor, .atlas)
        let root = LevelAssetPaths.root(set: name, .floor)
        let url = try SpriteSheetLoader.resourceURL(
            named: atlasName,
            extensions: ["json"],
            root: root,
            bundle: bundle
        )
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(FloorTileSet.self, from: data)
    }
}

enum FloorTileSetError: Error, Equatable {
    case missingSet(String)
    case emptyFloorTiles(String)
}
