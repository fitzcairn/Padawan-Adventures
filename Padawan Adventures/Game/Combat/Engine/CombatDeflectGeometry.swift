import CoreGraphics
import Foundation

/// Pure layout math for the deflect arena's isometric rings.
///
/// Scene space matches `CombatDeflectScene`: bottom-left origin, the player's feet at
/// `(width / 2, 0)`. Rings sit evenly on the upper arc of the outer isometric ellipse
/// (the lower half is off-screen by design).
nonisolated struct CombatDeflectGeometry: Equatable, Sendable {
    /// Outer ring's top edge, as a fraction of scene height above the bottom.
    static let outerTopHeightFraction: CGFloat = 0.40
    /// Where the small rings sit along the outer radius (0 = on the player, 1 = outer edge).
    /// Raise this if the rings crowd each other.
    static let ringOrbitFraction: CGFloat = 0.62 * 1.2
    /// Small-ring diameter as a multiple of the player's visible sprite width.
    /// Lower this if the rings overlap.
    static let ringDiameterScale: CGFloat = 1.0
    /// Fallback squash when the isometric config is degenerate (49 / 80 from app.yaml).
    static let defaultSquash: CGFloat = 0.6125
    /// Leftmost ring angle on the upper arc (135°). Matches the classic 3-ring NW seat.
    static let arcStartAngle: CGFloat = 3 * .pi / 4
    /// Rightmost ring angle on the upper arc (45°). Matches the classic 3-ring NE seat.
    static let arcEndAngle: CGFloat = .pi / 4

    let sceneSize: CGSize
    /// Ellipse height / width for the isometric projection (`tile_height / tile_width`).
    let squash: CGFloat
    /// Visible (opaque) width of the player sprite in scene points.
    let playerSpriteWidth: CGFloat
    /// Number of deflection circles (2…6).
    let ringCount: Int

    init(
        sceneSize: CGSize,
        squash: CGFloat,
        playerSpriteWidth: CGFloat,
        ringCount: Int = CombatDeflectConfig.defaultRingCount
    ) {
        self.sceneSize = CGSize(
            width: sceneSize.width.isFinite ? max(sceneSize.width, 1) : 1,
            height: sceneSize.height.isFinite ? max(sceneSize.height, 1) : 1
        )
        let raw = squash.isFinite ? squash : Self.defaultSquash
        self.squash = min(max(raw, 0.15), 1)
        self.playerSpriteWidth = playerSpriteWidth.isFinite ? max(playerSpriteWidth, 1) : 1
        self.ringCount = min(
            max(ringCount, CombatDeflectConfig.minRingCount),
            CombatDeflectConfig.maxRingCount
        )
    }

    /// Player feet: bottom-center of the scene, and the outer ring's origin.
    var center: CGPoint { CGPoint(x: sceneSize.width * 0.5, y: 0) }

    /// Rings left to right.
    var rings: [CombatDeflectRing] { CombatDeflectRing.all(count: ringCount) }

    /// `ry` puts the ring's top edge at 40% of scene height; `rx = ry / squash`
    /// so the ellipse reads as a circle lying flat in the isometric projection.
    var outerRadii: CGSize {
        let ry = sceneSize.height * Self.outerTopHeightFraction
        return CGSize(width: ry / squash, height: ry)
    }

    /// Small-ring radii. The diameter tracks the player's visible sprite width, capped
    /// so neighbouring rings always keep a visible gap on narrow scenes or wide sprites.
    var ringRadii: CGSize {
        let desired = playerSpriteWidth * Self.ringDiameterScale * 0.5
        let rx = min(desired, maxRingRadiusX)
        return CGSize(width: rx, height: rx * squash)
    }

    /// Distance between the two closest adjacent ring centers.
    var minimumRingSpacing: CGFloat {
        guard ringCount >= 2 else { return outerRadii.width * Self.ringOrbitFraction }
        let a = ringCenter(CombatDeflectRing(0))
        let b = ringCenter(CombatDeflectRing(1))
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Treats the rings as circles of radius `rx` (conservative, since `ry < rx`) and
    /// leaves 10% of the spacing as a gap.
    private var maxRingRadiusX: CGFloat {
        max(minimumRingSpacing * 0.5 * 0.9, 1)
    }

    /// Evenly spaced angle on the upper isometric arc for `ring`.
    func angle(for ring: CombatDeflectRing) -> CGFloat {
        Self.angle(for: ring.index, ringCount: ringCount)
    }

    /// Evenly spaced angles from `arcStartAngle` (left) to `arcEndAngle` (right).
    static func angle(for index: Int, ringCount: Int) -> CGFloat {
        let count = max(ringCount, 1)
        guard count > 1 else { return .pi / 2 }
        let t = CGFloat(index) / CGFloat(count - 1)
        return arcStartAngle + (arcEndAngle - arcStartAngle) * t
    }

    func ringCenter(_ ring: CombatDeflectRing) -> CGPoint {
        pointOnOrbit(angle: angle(for: ring))
    }

    /// Seat on the small-ring orbit at `angle` (radians, same convention as `angle(for:)`).
    func pointOnOrbit(angle: CGFloat) -> CGPoint {
        let t = Self.ringOrbitFraction
        return CGPoint(
            x: center.x + outerRadii.width * t * cos(angle),
            y: center.y + outerRadii.height * t * sin(angle)
        )
    }

    /// Cosine ease-in-out on `t` in 0…1. Used by the wrong-tap orbit so
    /// `SKAction.customAction` (which ignores `timingMode`) still eases.
    static func easeInEaseOut(_ t: CGFloat) -> CGFloat {
        let t = min(max(t, 0), 1)
        return 0.5 - 0.5 * cos(.pi * t)
    }

    /// Point on the upper-arc orbit between `from` and `to`, with cosine ease-in-out.
    func pointOnOrbit(from fromAngle: CGFloat, to toAngle: CGFloat, t: CGFloat) -> CGPoint {
        let eased = Self.easeInEaseOut(t)
        return pointOnOrbit(angle: fromAngle + (toAngle - fromAngle) * eased)
    }

    /// The letter overlays the top of its ring.
    func ringLabelPosition(_ ring: CombatDeflectRing) -> CGPoint {
        let c = ringCenter(ring)
        return CGPoint(x: c.x, y: c.y + ringRadii.height)
    }

    func ringRect(_ ring: CombatDeflectRing) -> CGRect {
        Self.rect(center: ringCenter(ring), radii: ringRadii)
    }

    /// Point on `ring`'s elliptical border nearest `point` (ray from ring center through `point`).
    func borderPoint(on ring: CombatDeflectRing, nearestTo point: CGPoint) -> CGPoint {
        let c = ringCenter(ring)
        let rx = max(ringRadii.width, 1)
        let ry = max(ringRadii.height, 1)
        let dx = point.x - c.x
        let dy = point.y - c.y
        // Unit-circle space, then snap to the ellipse rim.
        let nx = dx / rx
        let ny = dy / ry
        let length = (nx * nx + ny * ny).squareRoot()
        guard length > 0.000_1 else {
            // Degenerate: projectile on the center — pick the outward (toward top) rim.
            return CGPoint(x: c.x, y: c.y + ry)
        }
        return CGPoint(x: c.x + (nx / length) * rx, y: c.y + (ny / length) * ry)
    }

    var outerRect: CGRect { Self.rect(center: center, radii: outerRadii) }

    private static func rect(center: CGPoint, radii: CGSize) -> CGRect {
        CGRect(
            x: center.x - radii.width,
            y: center.y - radii.height,
            width: radii.width * 2,
            height: radii.height * 2
        )
    }

    /// Ring whose padded ellipse contains `point`, nearest first when they overlap.
    /// `padding` (>= 1) grows tap targets for small fingers.
    func hitTest(_ point: CGPoint, padding: CGFloat = 1.6) -> CombatDeflectRing? {
        var best: (ring: CombatDeflectRing, normalized: CGFloat)?
        for ring in rings {
            let c = ringCenter(ring)
            let rx = max(ringRadii.width * padding, 1)
            let ry = max(ringRadii.height * padding, 1)
            let nx = (point.x - c.x) / rx
            let ny = (point.y - c.y) / ry
            let distance = nx * nx + ny * ny
            guard distance <= 1 else { continue }
            if let current = best, distance >= current.normalized { continue }
            best = (ring, distance)
        }
        return best?.ring
    }
}
