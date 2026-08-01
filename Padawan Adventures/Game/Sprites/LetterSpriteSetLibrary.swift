import Foundation
import SpriteKit
import UIKit

/// Session-scoped cache of one active letter glyph set's textures.
///
/// Loads `Levels/{set}/{set}-letters-spritesheet.png` + atlas.
/// Switching levels replaces the previous set.
typealias LetterSpriteSetLibrary = AtlasSpriteSetLibrary<LetterSpriteSetAtlas>

extension AtlasSpriteSetLibrary where Provider == LetterSpriteSetAtlas {
    var letterSet: LetterSpriteSet? { loadedSet }

    /// Case-sensitive first; if missing, try opposite case; else nil.
    func texture(forLetter letter: String) -> SKTexture? {
        let key = letter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        if let texture = texture(key) { return texture }
        if let texture = texture(key.uppercased()) { return texture }
        if let texture = texture(key.lowercased()) { return texture }
        return nil
    }

    func seedForTesting(letterSet: LetterSpriteSet, textures: [String: SKTexture]) {
        seedForTesting(set: letterSet, textures: textures)
    }
}

/// Shared factory for letter glyph nodes sized into a square.
@MainActor
enum LetterSpriteFactory {
    /// Aspect-fit letter into a square of `side`; returns nil when the texture is missing.
    static func sprite(
        letter: String,
        side: CGFloat,
        library: LetterSpriteSetLibrary
    ) -> SKSpriteNode? {
        guard side > 0, let texture = library.texture(forLetter: letter) else { return nil }
        let node = SKSpriteNode(texture: texture)
        let texSize = texture.size()
        let maxDim = max(texSize.width, texSize.height)
        guard maxDim > 0 else { return nil }
        let scale = side / maxDim
        node.size = CGSize(width: texSize.width * scale, height: texSize.height * scale)
        return node
    }
}
