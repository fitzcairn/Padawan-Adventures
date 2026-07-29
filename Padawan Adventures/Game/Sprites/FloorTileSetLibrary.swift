import Foundation
import SpriteKit
import UIKit

/// Session-scoped cache of one active floor tile set's textures.
///
/// Loads `Sprites/Floor/{set}/Baked/{set}-floor-spritesheet.png` + atlas.
/// Switching levels replaces the previous set.
@MainActor
final class FloorTileSetLibrary {
    private(set) var setName: String?
    private(set) var tileSet: FloorTileSet?
    private var textures: [String: SKTexture] = [:]
    private let bundle: Bundle

    var isLoaded: Bool { tileSet != nil }

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    /// Loads (or reloads) the named floor set. Drops prior textures when the name changes.
    func ensureLoaded(set name: String, onProgress: ((Double) -> Void)? = nil) async {
        if setName == name, tileSet != nil {
            onProgress?(1)
            return
        }

        onProgress?(0)
        do {
            let loaded = try FloorTileSet.loadFromBundle(set: name, bundle: bundle)
            onProgress?(0.3)

            let sheetName = LevelAssetPaths.basename(set: name, .floor, .spritesheet)
            let root = LevelAssetPaths.root(set: name, .floor)
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
            for (index, tid) in keys.enumerated() {
                guard let frame = loaded.frames[tid] else { continue }
                nextTextures[tid] = SpriteSheetLoader.makeSubrectTexture(
                    x: frame.x,
                    y: frame.y,
                    w: frame.w,
                    h: frame.h,
                    sheetWidth: sheetW,
                    sheetHeight: sheetH,
                    parent: parent
                )
                if index % 16 == 0 {
                    onProgress?(0.5 + 0.5 * Double(index) / Double(max(keys.count, 1)))
                }
            }

            tileSet = loaded
            setName = name
            textures = nextTextures
            onProgress?(1)
        } catch {
            print("FloorTileSetLibrary: failed to load set '\(name)' — \(error)")
            tileSet = nil
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

    func frame(_ tileID: String) -> FloorTileSet.Frame? {
        tileSet?.frames[tileID]
    }

    /// Testing seam: inject a set without reading the bundle.
    func seedForTesting(tileSet: FloorTileSet, textures: [String: SKTexture]) {
        self.tileSet = tileSet
        self.setName = tileSet.meta.floorSet
        self.textures = textures
    }
}
