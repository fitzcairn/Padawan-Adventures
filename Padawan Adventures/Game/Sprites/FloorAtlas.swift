import CoreGraphics
import Foundation

/// Parametric atlas for the floor spritesheet (5×5 animation blocks × 11×11 tiles).
nonisolated struct FloorAtlas: Codable, Equatable, Sendable {
    var meta: Meta

    struct Meta: Codable, Equatable, Sendable {
        var size: Size
        var durationS: Double
        var blocks: Blocks
        var grid: Grid

        enum CodingKeys: String, CodingKey {
            case size
            case durationS = "duration_s"
            case blocks
            case grid
        }
    }

    struct Size: Codable, Equatable, Sendable {
        var w: Int
        var h: Int
    }

    struct Blocks: Codable, Equatable, Sendable {
        var cols: Int
        var rows: Int
        var width: Int
        var height: Int
    }

    struct Grid: Codable, Equatable, Sendable {
        var cols: Int
        var rows: Int
    }

    /// Pixel rect for one animation frame of the tile at `(tileRow, tileCol)`.
    /// Frame index is row-major across the block grid (0…blocks.cols*blocks.rows-1).
    func frameRect(tileRow: Int, tileCol: Int, frameIndex: Int) -> CGRect? {
        let blockCols = meta.blocks.cols
        let blockRows = meta.blocks.rows
        let frameCount = blockCols * blockRows
        guard frameIndex >= 0, frameIndex < frameCount,
              tileRow >= 0, tileRow < meta.grid.rows,
              tileCol >= 0, tileCol < meta.grid.cols,
              meta.blocks.width > 0, meta.blocks.height > 0,
              meta.grid.cols > 0, meta.grid.rows > 0 else {
            return nil
        }

        let blockCol = frameIndex % blockCols
        let blockRow = frameIndex / blockCols
        let blockOriginX = blockCol * meta.blocks.width
        let blockOriginY = blockRow * meta.blocks.height

        let x0 = blockOriginX + Self.dividedOrigin(tileCol, total: meta.blocks.width, count: meta.grid.cols)
        let x1 = blockOriginX + Self.dividedOrigin(tileCol + 1, total: meta.blocks.width, count: meta.grid.cols)
        let y0 = blockOriginY + Self.dividedOrigin(tileRow, total: meta.blocks.height, count: meta.grid.rows)
        let y1 = blockOriginY + Self.dividedOrigin(tileRow + 1, total: meta.blocks.height, count: meta.grid.rows)

        let width = x1 - x0
        let height = y1 - y0
        guard width > 0, height > 0 else { return nil }
        return CGRect(x: x0, y: y0, width: width, height: height)
    }

    var frameCount: Int {
        meta.blocks.cols * meta.blocks.rows
    }

    /// Equal per-frame duration when `meta.duration_s` is set.
    func frameDurationSeconds() -> TimeInterval {
        let count = max(frameCount, 1)
        let total = meta.durationS > 0 ? meta.durationS : Double(count) / 12.0
        return total / Double(count)
    }

    static func decode(from data: Data) throws -> FloorAtlas {
        try JSONDecoder().decode(FloorAtlas.self, from: data)
    }

    /// Evenly distributes remainder pixels: origin of cell `index` in a `total`-wide span split into `count` cells.
    static func dividedOrigin(_ index: Int, total: Int, count: Int) -> Int {
        Int((Double(index) * Double(total) / Double(count)).rounded())
    }
}
