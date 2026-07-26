import CoreGraphics
import Foundation

/// Per-frame diamond / ground-contact anchor baked into the floor atlas.
nonisolated struct FloorAnchor: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Equatable, Sendable {
        case tile
        case prop
    }

    /// Diamond centre (tile) or ground contact (prop), in frame pixels, top-left origin.
    var x: CGFloat
    var y: CGFloat
    /// Diamond width in frame pixels. Used for tile scaling; ignored for props.
    var diamondWidth: CGFloat
    var kind: Kind
    /// Prop display width as a fraction of tile width. Defaults to 1.
    var scale: CGFloat

    enum CodingKeys: String, CodingKey {
        case x
        case y
        case diamondWidth = "diamond_w"
        case kind
        case scale
    }

    init(x: CGFloat, y: CGFloat, diamondWidth: CGFloat, kind: Kind, scale: CGFloat = 1) {
        self.x = x
        self.y = y
        self.diamondWidth = diamondWidth
        self.kind = kind
        self.scale = scale
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        x = try container.decode(CGFloat.self, forKey: .x)
        y = try container.decode(CGFloat.self, forKey: .y)
        diamondWidth = try container.decode(CGFloat.self, forKey: .diamondWidth)
        kind = try container.decode(Kind.self, forKey: .kind)
        scale = try container.decodeIfPresent(CGFloat.self, forKey: .scale) ?? 1
    }
}
