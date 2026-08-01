import Foundation
import SpriteKit
import UIKit

/// Session-scoped cache of one active world gate wall sprite set.
///
/// Loads `Levels/{set}/{set}-gate-spritesheet.png` + atlas.
/// Switching levels replaces the previous set. Uses the same set name as the
/// level floor set (`1-tython`, …).
typealias GateSpriteSetLibrary = AtlasSpriteSetLibrary<GateSpriteSetAtlas>

extension AtlasSpriteSetLibrary where Provider == GateSpriteSetAtlas {
    var gateSet: GateSpriteSet? { loadedSet }

    func texture(for axis: GateSpriteSet.Axis) -> SKTexture? {
        texture(axis.rawValue)
    }

    func frame(for axis: GateSpriteSet.Axis) -> GateSpriteSet.Frame? {
        loadedSet?.frame(for: axis)
    }

    func seedForTesting(gateSet: GateSpriteSet, textures: [String: SKTexture]) {
        seedForTesting(set: gateSet, textures: textures)
    }
}
