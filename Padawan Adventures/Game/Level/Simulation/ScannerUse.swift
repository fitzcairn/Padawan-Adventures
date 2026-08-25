import Foundation

/// Resolves a world-HUD scanner tap to a reveal centered on the player.
nonisolated enum ScannerUse {
    static let itemID = "merchant-ware-scanner"
    static let radius = AreaScanUse.radius

    static func origin(in world: GameWorld) -> GridCoord {
        world.playerPosition ?? world.spawn
    }
}
