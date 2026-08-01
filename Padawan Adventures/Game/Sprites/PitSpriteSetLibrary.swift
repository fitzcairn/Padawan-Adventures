import Foundation
import SpriteKit
import UIKit

/// Session-scoped cache of one active pit platform tile set's textures.
///
/// Loads `Levels/{set}/{set}-pit-spritesheet.png` + atlas.
/// Switching levels replaces the previous set.
typealias PitSpriteSetLibrary = AtlasSpriteSetLibrary<PitSpriteSetAtlas>

extension AtlasSpriteSetLibrary where Provider == PitSpriteSetAtlas {
    var pitSet: PitSpriteSet? { loadedSet }

    /// Sorted tile ids from the loaded set (empty when unloaded).
    var tileIDs: [String] { loadedSet?.tileIDs ?? [] }

    /// Uniform random tile texture from the loaded set, or nil when empty.
    func randomTexture(using rng: inout some RandomNumberGenerator) -> SKTexture? {
        let ids = tileIDs
        guard !ids.isEmpty else { return nil }
        let index = Int.random(in: 0..<ids.count, using: &rng)
        return texture(ids[index])
    }

    func seedForTesting(pitSet: PitSpriteSet, textures: [String: SKTexture]) {
        seedForTesting(set: pitSet, textures: textures)
    }
}

/// Shared factory for pit platform nodes sized into a square.
@MainActor
enum PitSpriteFactory {
    /// Aspect-fit platform into a square of `side`; returns nil when the texture is missing.
    static func sprite(texture: SKTexture, side: CGFloat) -> SKSpriteNode? {
        guard side > 0 else { return nil }
        let node = SKSpriteNode(texture: texture)
        let texSize = texture.size()
        let maxDim = max(texSize.width, texSize.height)
        guard maxDim > 0 else { return nil }
        let scale = side / maxDim
        node.size = CGSize(width: texSize.width * scale, height: texSize.height * scale)
        return node
    }
}
