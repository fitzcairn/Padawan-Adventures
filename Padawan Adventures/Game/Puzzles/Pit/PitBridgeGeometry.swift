import CoreGraphics
import Foundation

/// Layout math for the pit-bridge arena (pads, slots, tray). Pure and unit-testable.
nonisolated struct PitBridgeGeometry: Equatable, Sendable {
    /// Tray tiles sit this fraction up the scene (inside the bottom 30%).
    static let trayCenterYFraction: CGFloat = 0.15
    /// Tray tile centers as fractions of scene width.
    static let trayXFractions: [CGFloat] = [0.25, 0.5, 0.75]
    /// Drop hit radius as a fraction of the tile side.
    static let dropRadiusScale: CGFloat = 0.6

    var sceneSize: CGSize
    /// AABB of the 2x2 isometric floor block used for each side pad.
    var padSize: CGSize
    /// Number of bridge slots (== words this session).
    var slotCount: Int

    var leftPadRect: CGRect {
        let padY = (sceneSize.height - padSize.height) * 0.5
        return CGRect(x: 0, y: padY, width: padSize.width, height: padSize.height)
    }

    var rightPadRect: CGRect {
        let padY = (sceneSize.height - padSize.height) * 0.5
        return CGRect(
            x: sceneSize.width - padSize.width,
            y: padY,
            width: padSize.width,
            height: padSize.height
        )
    }

    /// One isometric tile wide — half the 2x2 pad footprint.
    var tileSide: CGFloat {
        padSize.width * 0.5
    }

    var slotSpacing: CGFloat {
        let count = max(slotCount, 1)
        return (rightPadRect.minX - leftPadRect.maxX) / CGFloat(count + 1)
    }

    func slotCenter(_ index: Int) -> CGPoint {
        CGPoint(
            x: leftPadRect.maxX + slotSpacing * CGFloat(index + 1),
            y: leftPadRect.midY
        )
    }

    func trayCenter(_ index: Int) -> CGPoint {
        let fractions = Self.trayXFractions
        let fraction = fractions[index % fractions.count]
        let x = sceneSize.width * fraction
        let preferredY = sceneSize.height * Self.trayCenterYFraction
        let minY = tileSide * 0.6
        let maxY = leftPadRect.minY - tileSide * 0.6
        let y = max(minY, min(preferredY, maxY))
        return CGPoint(x: x, y: y)
    }

    func isDrop(_ point: CGPoint, onSlot index: Int) -> Bool {
        let center = slotCenter(index)
        let radius = tileSide * Self.dropRadiusScale
        return hypot(point.x - center.x, point.y - center.y) <= radius
    }
}
