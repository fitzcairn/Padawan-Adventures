import SpriteKit
import UIKit

extension PlaceholderFactory {
    // Explicit sRGB so SKShapeNode fillColor round-trips equal (UIColor.white is gray-space).
    static let floorColor = UIColor(red: 1, green: 1, blue: 1, alpha: 1)
    /// Dark brown pit fill so hazards read clearly against white floors.
    static let pitColor = UIColor(red: 0.28, green: 0.14, blue: 0.06, alpha: 1)
    /// Brighter gray so 1-tile partitions stay readable at fit-scale overview.
    static let wallColor = UIColor(white: 0.72, alpha: 1)
    /// Spelling gate (legacy single gate color).
    static let spellingGateColor = UIColor(red: 0.55, green: 0.9, blue: 0.55, alpha: 1)
    /// Letter-match gate.
    static let letterMatchGateColor = UIColor(red: 0.45, green: 0.75, blue: 1.0, alpha: 1)
    /// Word-plug gate.
    static let wordPlugGateColor = UIColor(red: 1.0, green: 0.78, blue: 0.35, alpha: 1)
    /// Ending-sound word-plug gate.
    static let endingSoundPlugGateColor = UIColor(red: 0.85, green: 0.55, blue: 1.0, alpha: 1)

    static func gateColor(for minigame: GateMinigameKind) -> UIColor {
        switch minigame {
        case .spelling: spellingGateColor
        case .letterMatch: letterMatchGateColor
        case .wordPlug: wordPlugGateColor
        case .endingSoundPlug: endingSoundPlugGateColor
        }
    }
    /// Raised roof fill between wall tops.
    static let ceilingColor = UIColor(red: 0.55, green: 0.55, blue: 0.55, alpha: 1)
    /// Screen-space Y drop for pit tiles so voids read below the surrounding floor.
    static let pitDropPixels: CGFloat = 5

    /// World position for a floor cell, including the pit drop when `isPit`.
    static func floorScreenPosition(
        for tile: Tile,
        at coord: GridCoord,
        config: IsometricConfig
    ) -> CGPoint {
        let screen = IsometricMath.gridToScreen(coord, config: config)
        guard tile.isPit else { return screen }
        return CGPoint(x: screen.x, y: screen.y - pitDropPixels)
    }

    /// Nested z biases must stay well below one depth step and the entity/wall
    /// half-step (`entitySortValue` = depth + 0.5). Floors use a lower parent band;
    /// walls/entities share the occlusion band. With `ignoresSiblingOrder`,
    /// SpriteKit sorts by accumulated z — integer face offsets (+1/+2) used to
    /// let sprites draw over front wall sides while wall tops still won.
    static let wallFaceLeftZ: CGFloat = 0.01
    static let wallFaceRightZ: CGFloat = 0.02
    static let wallFaceTopZ: CGFloat = 0.03
    static let entityBodyZ: CGFloat = 0.01
    static let entityLabelZ: CGFloat = 0.02

    static let playerFillColor = UIColor(red: 0.15, green: 0.55, blue: 1.0, alpha: 1)
    static let defaultEntityFillColor = UIColor(white: 0.9, alpha: 1)

    static let pickupIconSize: CGFloat = 30
    static let pickupBounceAmplitude: CGFloat = 5
    static let healthPickupColor = UIColor.systemRed
    static let energyPickupColor = UIColor.systemYellow
    static let treasurePickupColor = UIColor(red: 0.2, green: 0.75, blue: 0.35, alpha: 1)
}
