import CoreGraphics
import Testing
@testable import Padawan_Adventures

struct CombatDeflectGeometryTests {
    /// Landscape scene with the shipped isometric squash (49 / 80).
    private func makeGeometry(
        width: CGFloat = 852,
        height: CGFloat = 393,
        squash: CGFloat = 49.0 / 80.0,
        playerSpriteWidth: CGFloat = 120
    ) -> CombatDeflectGeometry {
        CombatDeflectGeometry(
            sceneSize: CGSize(width: width, height: height),
            squash: squash,
            playerSpriteWidth: playerSpriteWidth
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
        let nw = geo.ringCenter(.northwest)
        let up = geo.ringCenter(.up)
        let ne = geo.ringCenter(.northeast)
        #expect(nw.x < up.x)
        #expect(up.x < ne.x)
        #expect(abs(up.x - geo.center.x) < 0.001)
    }

    @Test func upRingIsTheHighestAndTheDiagonalsAreSymmetric() {
        let geo = makeGeometry()
        let nw = geo.ringCenter(.northwest)
        let up = geo.ringCenter(.up)
        let ne = geo.ringCenter(.northeast)
        #expect(up.y > nw.y)
        #expect(abs(nw.y - ne.y) < 0.001)
        #expect(abs((geo.center.x - nw.x) - (ne.x - geo.center.x)) < 0.001)
    }

    @Test func ringsSitInsideTheOuterRing() {
        let geo = makeGeometry()
        for ring in CombatDeflectRing.allCases {
            let c = geo.ringCenter(ring)
            let nx = (c.x - geo.center.x) / geo.outerRadii.width
            let ny = (c.y - geo.center.y) / geo.outerRadii.height
            #expect(nx * nx + ny * ny < 1)
            #expect(c.y > 0)
        }
    }

    @Test(arguments: [40.0, 80.0, 120.0, 400.0] as [CGFloat])
    func ringsNeverOverlap(playerSpriteWidth: CGFloat) {
        let geo = makeGeometry(playerSpriteWidth: playerSpriteWidth)
        let rings = CombatDeflectRing.allCases
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

    @Test func labelSitsOnTopOfItsRing() {
        let geo = makeGeometry()
        for ring in CombatDeflectRing.allCases {
            let center = geo.ringCenter(ring)
            let label = geo.ringLabelPosition(ring)
            #expect(abs(label.x - center.x) < 0.001)
            #expect(abs(label.y - (center.y + geo.ringRadii.height)) < 0.001)
        }
    }

    @Test func ringRectMatchesTheCenterAndRadii() {
        let geo = makeGeometry()
        let rect = geo.ringRect(.up)
        let center = geo.ringCenter(.up)
        #expect(abs(rect.midX - center.x) < 0.001)
        #expect(abs(rect.midY - center.y) < 0.001)
        #expect(abs(rect.width - geo.ringRadii.width * 2) < 0.001)
        #expect(abs(rect.height - geo.ringRadii.height * 2) < 0.001)
    }

    @Test func hitTestFindsTheRingUnderATap() {
        let geo = makeGeometry()
        for ring in CombatDeflectRing.allCases {
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
        let up = geo.ringCenter(.up)
        let ne = geo.ringCenter(.northeast)
        // Just off the up ring's center, biased toward the northeast ring.
        let biased = CGPoint(x: up.x + (ne.x - up.x) * 0.15, y: up.y)
        #expect(geo.hitTest(biased) == .up)
    }

    @Test func paddingWidensTapTargetsForSmallFingers() {
        let geo = makeGeometry()
        let up = geo.ringCenter(.up)
        // Outside the drawn ellipse on Y, but inside the padded target.
        let justOutside = CGPoint(x: up.x, y: up.y + geo.ringRadii.height * 1.3)
        #expect(geo.hitTest(justOutside, padding: 1) == nil)
        #expect(geo.hitTest(justOutside, padding: 1.6) == .up)
    }

    @Test func degenerateInputsAreClampedInsteadOfProducingNaN() {
        let geo = CombatDeflectGeometry(
            sceneSize: CGSize(width: 0, height: 0),
            squash: 0,
            playerSpriteWidth: 0
        )
        #expect(geo.sceneSize.width >= 1)
        #expect(geo.sceneSize.height >= 1)
        #expect(geo.squash > 0)
        #expect(geo.outerRadii.width.isFinite)
        #expect(geo.outerRadii.height.isFinite)
        #expect(geo.ringRadii.width.isFinite)
        for ring in CombatDeflectRing.allCases {
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
}
