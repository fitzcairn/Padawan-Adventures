import Foundation
import SpriteKit
import UIKit

/// Session-scoped cache of one active world gate wall sprite set.
///
/// Loads `Sprites/Gate/Floor/{set}/Baked/{set}-gate-spritesheet.png` + atlas.
/// Switching levels replaces the previous set. Uses the same set name as the
/// level floor set (`1-tython`, …).
@MainActor
final class GateSpriteSetLibrary {
    private(set) var setName: String?
    private(set) var gateSet: GateSpriteSet?
    private var textures: [String: SKTexture] = [:]
    private let bundle: Bundle

    var isLoaded: Bool { gateSet != nil }

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    /// Loads (or reloads) the named gate set. Drops prior textures when the name changes.
    func ensureLoaded(set name: String, onProgress: ((Double) -> Void)? = nil) async {
        if setName == name, gateSet != nil {
            onProgress?(1)
            return
        }

        onProgress?(0)
        do {
            let loaded = try GateSpriteSet.loadFromBundle(set: name, bundle: bundle)
            onProgress?(0.3)

            let sheetName = "\(name)-gate-spritesheet"
            let root = "Sprites/Gate/Floor/\(name)"
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
            let keys = loaded.axisIDs
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
                onProgress?(0.5 + 0.5 * Double(index + 1) / Double(max(keys.count, 1)))
            }

            gateSet = loaded
            setName = name
            textures = nextTextures
            onProgress?(1)
        } catch {
            print("GateSpriteSetLibrary: failed to load set '\(name)' — \(error)")
            gateSet = nil
            setName = nil
            textures = [:]
            onProgress?(1)
        }
    }

    func texture(for axis: GateSpriteSet.Axis) -> SKTexture? {
        textures[axis.rawValue]
    }

    func frame(for axis: GateSpriteSet.Axis) -> GateSpriteSet.Frame? {
        gateSet?.frame(for: axis)
    }

    func allTextures() -> [SKTexture] {
        Array(textures.values)
    }

    /// Testing seam: inject a set without reading the bundle.
    func seedForTesting(gateSet: GateSpriteSet, textures: [String: SKTexture]) {
        self.gateSet = gateSet
        self.setName = gateSet.meta.gateSet
        self.textures = textures
    }
}
