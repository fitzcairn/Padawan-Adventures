import Foundation
import SpriteKit
import UIKit

/// Session-scoped cache of one active letter glyph set's textures.
///
/// Loads `Sprites/Letters/{set}/Baked/{set}-letters-spritesheet.png` + atlas.
/// Switching levels replaces the previous set.
@MainActor
final class LetterSpriteSetLibrary {
    private(set) var setName: String?
    private(set) var letterSet: LetterSpriteSet?
    private var textures: [String: SKTexture] = [:]
    private let bundle: Bundle

    var isLoaded: Bool { letterSet != nil }

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    /// Loads (or reloads) the named letter set. Drops prior textures when the name changes.
    func ensureLoaded(set name: String, onProgress: ((Double) -> Void)? = nil) async {
        if setName == name, letterSet != nil {
            onProgress?(1)
            return
        }

        onProgress?(0)
        do {
            let loaded = try LetterSpriteSet.loadFromBundle(set: name, bundle: bundle)
            onProgress?(0.3)

            let sheetName = "\(name)-letters-spritesheet"
            let root = "Sprites/Letters/\(name)"
            let sheetURL = try SpriteSheetLoader.resourceURL(
                named: sheetName,
                extensions: ["png", "jpg", "jpeg"],
                root: root,
                bundle: bundle
            )
            guard let uiImage = UIImage(contentsOfFile: sheetURL.path),
                  let cgImage = uiImage.cgImage else {
                throw SpriteLoadError.invalidImage(sheetName)
            }
            onProgress?(0.5)

            let parent = SKTexture(image: UIImage(cgImage: cgImage, scale: 1, orientation: .up))
            parent.filteringMode = .nearest
            parent.usesMipmaps = false

            let sheetW = loaded.meta.size.w
            let sheetH = loaded.meta.size.h
            var nextTextures: [String: SKTexture] = [:]
            let keys = loaded.frames.keys.sorted()
            for (index, key) in keys.enumerated() {
                guard let frame = loaded.frames[key] else { continue }
                nextTextures[key] = SpriteSheetLoader.makeSubrectTexture(
                    x: frame.x,
                    y: frame.y,
                    w: frame.w,
                    h: frame.h,
                    sheetWidth: sheetW,
                    sheetHeight: sheetH,
                    parent: parent
                )
                if index % 8 == 0 {
                    onProgress?(0.5 + 0.5 * Double(index) / Double(max(keys.count, 1)))
                }
            }

            letterSet = loaded
            setName = name
            textures = nextTextures
            onProgress?(1)
        } catch {
            print("LetterSpriteSetLibrary: failed to load set '\(name)' — \(error)")
            letterSet = nil
            setName = nil
            textures = [:]
            onProgress?(1)
        }
    }

    /// Case-sensitive first; if missing, try opposite case; else nil.
    func texture(forLetter letter: String) -> SKTexture? {
        let key = letter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        if let texture = textures[key] { return texture }
        if let texture = textures[key.uppercased()] { return texture }
        if let texture = textures[key.lowercased()] { return texture }
        return nil
    }

    /// Testing seam: inject a set without reading the bundle.
    func seedForTesting(letterSet: LetterSpriteSet, textures: [String: SKTexture]) {
        self.letterSet = letterSet
        self.setName = letterSet.meta.letterSet
        self.textures = textures
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
