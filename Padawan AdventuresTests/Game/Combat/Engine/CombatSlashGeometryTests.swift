import CoreGraphics
import Testing
@testable import Padawan_Adventures

struct CombatSlashGeometryTests {
    private let center = CGPoint(x: 100, y: 100)
    private let side: CGFloat = 40
    private var square: CGRect {
        CGRect(x: center.x - side * 0.5, y: center.y - side * 0.5, width: side, height: side)
    }

    @Test func throughCutIntersects() {
        let points = [
            CGPoint(x: 50, y: 100),
            CGPoint(x: 150, y: 100),
        ]
        #expect(CombatSlashGeometry.slashIntersectsRect(points: points, rect: square))
        #expect(CombatSlashGeometry.slashBisectsSquare(points: points, center: center, side: side))
    }

    @Test func diagonalThroughCutIntersects() {
        let points = [
            CGPoint(x: 60, y: 60),
            CGPoint(x: 140, y: 140),
        ]
        #expect(CombatSlashGeometry.slashIntersectsRect(points: points, rect: square))
    }

    @Test func pokeIntoSpriteCountsAsIntersection() {
        // Enter left edge and reverse out — not a bisect, but still a hit.
        let points = [
            CGPoint(x: 50, y: 100),
            CGPoint(x: 90, y: 100),
            CGPoint(x: 50, y: 100),
        ]
        #expect(CombatSlashGeometry.slashIntersectsRect(points: points, rect: square))
        #expect(!CombatSlashGeometry.slashBisectsSquare(points: points, center: center, side: side))
    }

    @Test func pointInsideSpriteCountsAsIntersection() {
        let points = [
            CGPoint(x: 95, y: 95),
            CGPoint(x: 105, y: 105),
        ]
        #expect(CombatSlashGeometry.slashIntersectsRect(points: points, rect: square))
    }

    @Test func grazeAlongOutsideDoesNotIntersect() {
        let points = [
            CGPoint(x: 50, y: 100),
            CGPoint(x: 70, y: 100),
            CGPoint(x: 70, y: 140),
        ]
        #expect(!CombatSlashGeometry.slashIntersectsRect(points: points, rect: square))
    }

    @Test func missFarAwayDoesNotIntersect() {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 20, y: 20),
        ]
        #expect(!CombatSlashGeometry.slashIntersectsRect(points: points, rect: square))
    }

    @Test func wideSpriteRectAcceptsEdgeClip() {
        let wide = CGRect(x: 60, y: 90, width: 80, height: 20)
        let points = [
            CGPoint(x: 50, y: 100),
            CGPoint(x: 70, y: 100),
        ]
        #expect(CombatSlashGeometry.slashIntersectsRect(points: points, rect: wide))
    }
}
