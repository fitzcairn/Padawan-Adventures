import Foundation
import SpriteKit
import UIKit

/// Session-scoped cache of one active floor tile set's textures.
///
/// Loads `Levels/{set}/{set}-floor-spritesheet.png` + atlas.
/// Switching levels replaces the previous set.
typealias FloorTileSetLibrary = AtlasSpriteSetLibrary<FloorTileSetAtlas>

extension AtlasSpriteSetLibrary where Provider == FloorTileSetAtlas {
    var tileSet: FloorTileSet? { loadedSet }

    func frame(_ tileID: String) -> FloorTileSet.Frame? {
        loadedSet?.frames[tileID]
    }

    func seedForTesting(tileSet: FloorTileSet, textures: [String: SKTexture]) {
        seedForTesting(set: tileSet, textures: textures)
    }
}
