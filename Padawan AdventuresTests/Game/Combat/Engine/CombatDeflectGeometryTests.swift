import CoreGraphics
import Testing
@testable import Padawan_Adventures

struct CombatDeflectGeometryTests {
    /// Landscape scene with the shipped isometric squash (49 / 80).
    private func makeGeometry(
        width: CGFloat = 852,
        height: CGFloat = 393,
        squash: CGFloat = 49.0 / 80.0,
        playerSpriteWidth: CGFloat = 120,
        ringCount: Int = 3
    ) -> CombatDeflectGeometry {
        CombatDeflectGeometry(
            sceneSize: CGSize(width: width, height: height),
            squash: squash,
            playerSpriteWidth: playerSpriteWidth,
            ringCount: ringCount
        )
    }

    @Test func outerRingIsCenteredOnThePlayersFeet() {
        let geo = makeGeometry()
        #expect(geo.center == CGPoint(x: 426, y: 0))
    }

    @Test func outerRingTopSitsAt40PercentOfSceneHeight() {
        let geo = makeGeometry(height: 400)
        #expect(abs(geo.outerRect.maxY - 160) < 0.001)
        #expect(abs(geo.outerRadii.height - 160) < 0.001)
    }

    @Test func outerRingIsWiderThanTallSoItReadsAsAFlatCircle() {
        let geo = makeGeometry(squash: 0.6125)
        #expect(geo.outerRadii.width > geo.outerRadii.height)
        // rx = ry / squash keeps the projected ellipse circular in world space.
        #expect(abs(geo.outerRadii.width * 0.6125 - geo.outerRadii.height) < 0.001)
    }

    @Test func smallRingDiameterMatchesThePlayerSpriteWidth() {
        let geo = makeGeometry(playerSpriteWidth: 80)
        #expect(abs(geo.ringRadii.width * 2 - 80) < 0.001)
        #expect(geo.ringRadii.height < geo.ringRadii.width)
    }

    @Test func ringDiameterIsCappedSoNeighboursKeepAGap() {
        let geo = makeGeometry(playerSpriteWidth: 4_000)
        #expect(geo.ringRadii.width * 2 < geo.minimumRingSpacing)
        // The cap must not depend on the sprite being absurd; it is the same bound.
        let wider = makeGeometry(playerSpriteWidth: 10_000)
        #expect(abs(wider.ringRadii.width - geo.ringRadii.width) < 0.001)
    }

    @Test func ringsAreOrderedLeftToRight() {
        let geo = makeGeometry()
        let left = geo.ringCenter(CombatDeflectRing(0))
        let mid = geo.ringCenter(CombatDeflectRing(1))
        let right = geo.ringCenter(CombatDeflectRing(2))
        #expect(left.x < mid.x)
        #expect(mid.x < right.x)
        #expect(abs(mid.x - geo.center.x) < 0.001)
    }

    @Test func threeRingLayoutMatchesClassicNWUpNEAngles() {
        let geo = makeGeometry(ringCount: 3)
        #expect(abs(geo.angle(for: CombatDeflectRing(0)) - 3 * .pi / 4) < 0.000_1)
        #expect(abs(geo.angle(for: CombatDeflectRing(1)) - .pi / 2) < 0.000_1)
        #expect(abs(geo.angle(for: CombatDeflectRing(2)) - .pi / 4) < 0.000_1)
    }

    @Test func upRingIsTheHighestAndTheDiagonalsAreSymmetric() {
        let geo = makeGeometry()
        let left = geo.ringCenter(CombatDeflectRing(0))
        let mid = geo.ringCenter(CombatDeflectRing(1))
        let right = geo.ringCenter(CombatDeflectRing(2))
        #expect(mid.y > left.y)
        #expect(abs(left.y - right.y) < 0.001)
        #expect(abs((geo.center.x - left.x) - (right.x - geo.center.x)) < 0.001)
    }

    @Test(arguments: [2, 3, 4, 5, 6])
    func ringsAreEvenlySpacedOnTheUpperArc(ringCount: Int) {
        let geo = makeGeometry(ringCount: ringCount)
        #expect(geo.rings.count == ringCount)
        let angles = geo.rings.map { geo.angle(for: $0) }
        #expect(abs(angles.first! - CombatDeflectGeometry.arcStartAngle) < 0.000_1)
        #expect(abs(angles.last! - CombatDeflectGeometry.arcEndAngle) < 0.000_1)
        if ringCount > 2 {
            let step = angles[1] - angles[0]
            for i in 1..<angles.count {
                #expect(abs((angles[i] - angles[i - 1]) - step) < 0.000_1)
            }
        }
        // Angles decrease left→right (from NW toward NE).
        for i in 1..<angles.count {
            #expect(angles[i] < angles[i - 1])
        }
    }

    @Test(arguments: [2, 3, 4, 5, 6])
    func ringsSitInsideTheOuterRing(ringCount: Int) {
        let geo = makeGeometry(ringCount: ringCount)
        for ring in geo.rings {
            let c = geo.ringCenter(ring)
            let nx = (c.x - geo.center.x) / geo.outerRadii.width
            let ny = (c.y - geo.center.y) / geo.outerRadii.height
            #expect(nx * nx + ny * ny < 1)
            #expect(c.y > 0)
        }
    }

    @Test(arguments: [2, 3, 4, 5, 6])
    func ringsNeverOverlap(ringCount: Int) {
        for playerSpriteWidth in [40.0, 80.0, 120.0, 400.0] as [CGFloat] {
            let geo = makeGeometry(playerSpriteWidth: playerSpriteWidth, ringCount: ringCount)
            let rings = geo.rings
            for (i, a) in rings.enumerated() {
                for b in rings.dropFirst(i + 1) {
                    let ca = geo.ringCenter(a)
                    let cb = geo.ringCenter(b)
                    let dx = ca.x - cb.x
                    let dy = ca.y - cb.y
                    let distance = (dx * dx + dy * dy).squareRoot()
                    // Ellipses touch at worst when centers are closer than 2 × rx.
                    #expect(distance > geo.ringRadii.width * 2)
                }
            }
        }
    }

    @Test func labelSitsOnTopOfItsRing() {
        let geo = makeGeometry()
        for ring in geo.rings {
            let center = geo.ringCenter(ring)
            let label = geo.ringLabelPosition(ring)
            #expect(abs(label.x - center.x) < 0.001)
            #expect(abs(label.y - (center.y + geo.ringRadii.height)) < 0.001)
        }
    }

    @Test func ringRectMatchesTheCenterAndRadii() {
        let geo = makeGeometry()
        let ring = CombatDeflectRing(1)
        let rect = geo.ringRect(ring)
        let center = geo.ringCenter(ring)
        #expect(abs(rect.midX - center.x) < 0.001)
        #expect(abs(rect.midY - center.y) < 0.001)
        #expect(abs(rect.width - geo.ringRadii.width * 2) < 0.001)
        #expect(abs(rect.height - geo.ringRadii.height * 2) < 0.001)
    }

    @Test(arguments: [2, 3, 4, 5, 6])
    func hitTestFindsTheRingUnderATap(ringCount: Int) {
        let geo = makeGeometry(ringCount: ringCount)
        for ring in geo.rings {
            #expect(geo.hitTest(geo.ringCenter(ring)) == ring)
        }
    }

    @Test func hitTestReturnsNilFarFromEveryRing() {
        let geo = makeGeometry()
        #expect(geo.hitTest(CGPoint(x: 10, y: 380)) == nil)
        #expect(geo.hitTest(CGPoint(x: 842, y: 380)) == nil)
    }

    @Test func hitTestPicksTheNearestRingWhenPaddedTargetsOverlap() {
        let geo = makeGeometry()
        let up = geo.ringCenter(CombatDeflectRing(1))
        let ne = geo.ringCenter(CombatDeflectRing(2))
        // Just off the up ring's center, biased toward the northeast ring.
        let biased = CGPoint(x: up.x + (ne.x - up.x) * 0.15, y: up.y)
        #expect(geo.hitTest(biased) == CombatDeflectRing(1))
    }

    @Test func paddingWidensTapTargetsForSmallFingers() {
        let geo = makeGeometry()
        let up = geo.ringCenter(CombatDeflectRing(1))
        // Outside the drawn ellipse on Y, but inside the padded target.
        let justOutside = CGPoint(x: up.x, y: up.y + geo.ringRadii.height * 1.3)
        #expect(geo.hitTest(justOutside, padding: 1) == nil)
        #expect(geo.hitTest(justOutside, padding: 1.6) == CombatDeflectRing(1))
    }

    @Test func degenerateInputsAreClampedInsteadOfProducingNaN() {
        let geo = CombatDeflectGeometry(
            sceneSize: CGSize(width: 0, height: 0),
            squash: 0,
            playerSpriteWidth: 0,
            ringCount: 0
        )
        #expect(geo.sceneSize.width >= 1)
        #expect(geo.sceneSize.height >= 1)
        #expect(geo.squash > 0)
        #expect(geo.ringCount == CombatDeflectConfig.minRingCount)
        #expect(geo.outerRadii.width.isFinite)
        #expect(geo.outerRadii.height.isFinite)
        #expect(geo.ringRadii.width.isFinite)
        for ring in geo.rings {
            #expect(geo.ringCenter(ring).x.isFinite)
            #expect(geo.ringCenter(ring).y.isFinite)
        }
    }

    @Test func nonFiniteInputsAreRejected() {
        let geo = CombatDeflectGeometry(
            sceneSize: CGSize(width: CGFloat.nan, height: CGFloat.infinity),
            squash: CGFloat.nan,
            playerSpriteWidth: CGFloat.nan
        )
        #expect(geo.sceneSize.width.isFinite)
        #expect(geo.sceneSize.height.isFinite)
        #expect(geo.squash.isFinite)
        #expect(geo.playerSpriteWidth.isFinite)
        #expect(geo.outerRadii.height.isFinite)
    }

    @Test func ringCountIsClampedToSupportedRange() {
        #expect(makeGeometry(ringCount: 1).ringCount == 2)
        #expect(makeGeometry(ringCount: 9).ringCount == 6)
    }

    @Test func borderPointNearestProjectileLiesOnTheRingRim() {
        let geo = makeGeometry()
        let ring = CombatDeflectRing(1)
        let center = geo.ringCenter(ring)
        let projectile = CGPoint(x: center.x + 200, y: center.y + 80)
        let border = geo.borderPoint(on: ring, nearestTo: projectile)

        let nx = (border.x - center.x) / geo.ringRadii.width
        let ny = (border.y - center.y) / geo.ringRadii.height
        #expect(abs(nx * nx + ny * ny - 1) < 0.001)

        // Same direction from the ring center as the projectile.
        let bdx = border.x - center.x
        let bdy = border.y - center.y
        let pdx = projectile.x - center.x
        let pdy = projectile.y - center.y
        #expect(bdx * pdx + bdy * pdy > 0)
        #expect(abs(bdx * pdy - bdy * pdx) < 0.01)
    }
}
