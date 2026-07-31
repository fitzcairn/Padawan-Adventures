import CoreGraphics
import Foundation

/// Pure layout math for the deflect arena's isometric rings.
///
/// Scene space matches `CombatDeflectScene`: bottom-left origin, the player's feet at
/// `(width / 2, 0)`. The outer ring is centered on the player, so its lower half sits
/// below the screen — that is intended.
nonisolated struct CombatDeflectGeometry: Equatable, Sendable {
    /// Outer ring's top edge, as a fraction of scene height above the bottom.
    static let outerTopHeightFraction: CGFloat = 0.40
    /// Where the small rings sit along the outer radius (0 = on the player, 1 = outer edge).
    /// Raise this if the rings crowd each other.
    static let ringOrbitFraction: CGFloat = 0.62
    /// Small-ring diameter as a multiple of the player's visible sprite width.
    /// Lower this if the rings overlap.
    static let ringDiameterScale: CGFloat = 1.0
    /// Fallback squash when the isometric config is degenerate (49 / 80 from app.yaml).
    static let defaultSquash: CGFloat = 0.6125

    let sceneSize: CGSize
    /// Ellipse height / width for the isometric projection (`tile_height / tile_width`).
    let squash: CGFloat
    /// Visible (opaque) width of the player sprite in scene points.
    let playerSpriteWidth: CGFloat

    init(sceneSize: CGSize, squash: CGFloat, playerSpriteWidth: CGFloat) {
        self.sceneSize = CGSize(
            width: sceneSize.width.isFinite ? max(sceneSize.width, 1) : 1,
            height: sceneSize.height.isFinite ? max(sceneSize.height, 1) : 1
        )
        let raw = squash.isFinite ? squash : Self.defaultSquash
        self.squash = min(max(raw, 0.15), 1)
        self.playerSpriteWidth = playerSpriteWidth.isFinite ? max(playerSpriteWidth, 1) : 1
    }

    /// Player feet: bottom-center of the scene, and the outer ring's origin.
    var center: CGPoint { CGPoint(x: sceneSize.width * 0.5, y: 0) }

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

    /// Distance between the two closest ring centers (a diagonal and the up ring).
    var minimumRingSpacing: CGFloat {
        let t = Self.ringOrbitFraction
        let c = cos(CGFloat.pi / 4)
        let dx = outerRadii.width * t * c
        let dy = outerRadii.height * t * (1 - c)
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Treats the rings as circles of radius `rx` (conservative, since `ry < rx`) and
    /// leaves 10% of the spacing as a gap.
    private var maxRingRadiusX: CGFloat {
        max(minimumRingSpacing * 0.5 * 0.9, 1)
    }

    /// Projected-space angles: 135 degrees (NW), 90 (up), 45 (NE).
    static func angle(for ring: CombatDeflectRing) -> CGFloat {
        switch ring {
        case .northwest: 3 * .pi / 4
        case .up: .pi / 2
        case .northeast: .pi / 4
        }
    }

    func ringCenter(_ ring: CombatDeflectRing) -> CGPoint {
        let theta = Self.angle(for: ring)
        let t = Self.ringOrbitFraction
        return CGPoint(
            x: center.x + outerRadii.width * t * cos(theta),
            y: center.y + outerRadii.height * t * sin(theta)
        )
    }

    /// The letter overlays the top of its ring.
    func ringLabelPosition(_ ring: CombatDeflectRing) -> CGPoint {
        let c = ringCenter(ring)
        return CGPoint(x: c.x, y: c.y + ringRadii.height)
    }

    func ringRect(_ ring: CombatDeflectRing) -> CGRect {
        Self.rect(center: ringCenter(ring), radii: ringRadii)
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
        for ring in CombatDeflectRing.allCases {
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
