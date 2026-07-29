import Foundation
import SpriteKit
import UIKit

/// Session-scoped cache of one active pit platform tile set's textures.
///
/// Loads `Sprites/Pit/{set}/Baked/{set}-pit-spritesheet.png` + atlas.
/// Switching levels replaces the previous set.
@MainActor
final class PitSpriteSetLibrary {
    private(set) var setName: String?
    private(set) var pitSet: PitSpriteSet?
    private var textures: [String: SKTexture] = [:]
    private let bundle: Bundle

    var isLoaded: Bool { pitSet != nil }

    /// Sorted tile ids from the loaded set (empty when unloaded).
    var tileIDs: [String] { pitSet?.tileIDs ?? [] }

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    /// Loads (or reloads) the named pit set. Drops prior textures when the name changes.
    func ensureLoaded(set name: String, onProgress: ((Double) -> Void)? = nil) async {
        if setName == name, pitSet != nil {
            onProgress?(1)
            return
        }

        onProgress?(0)
        do {
            let loaded = try PitSpriteSet.loadFromBundle(set: name, bundle: bundle)
            onProgress?(0.3)

            let sheetName = LevelAssetPaths.basename(set: name, .pit, .spritesheet)
            let root = LevelAssetPaths.root(set: name, .pit)
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
            let keys = loaded.tileIDs
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
                if index % 4 == 0 {
                    onProgress?(0.5 + 0.5 * Double(index) / Double(max(keys.count, 1)))
                }
            }

            pitSet = loaded
            setName = name
            textures = nextTextures
            onProgress?(1)
        } catch {
            print("PitSpriteSetLibrary: failed to load set '\(name)' — \(error)")
            pitSet = nil
            setName = nil
            textures = [:]
            onProgress?(1)
        }
    }

    func texture(_ tileID: String) -> SKTexture? {
        textures[tileID]
    }

    func allTextures() -> [SKTexture] {
        Array(textures.values)
    }

    /// Uniform random tile texture from the loaded set, or nil when empty.
    func randomTexture(using rng: inout some RandomNumberGenerator) -> SKTexture? {
        let ids = tileIDs
        guard !ids.isEmpty else { return nil }
        let index = Int.random(in: 0..<ids.count, using: &rng)
        return textures[ids[index]]
    }

    /// Testing seam: inject a set without reading the bundle.
    func seedForTesting(pitSet: PitSpriteSet, textures: [String: SKTexture]) {
        self.pitSet = pitSet
        self.setName = pitSet.meta.pitSet
        self.textures = textures
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
