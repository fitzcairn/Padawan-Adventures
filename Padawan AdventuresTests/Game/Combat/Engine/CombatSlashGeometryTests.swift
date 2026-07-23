import CoreGraphics
import Testing
@testable import Padawan_Adventures

struct CombatSlashGeometryTests {
    private let center = CGPoint(x: 100, y: 100)
    private let side: CGFloat = 40

    @Test func throughCutBisects() {
        let points = [
            CGPoint(x: 50, y: 100),
            CGPoint(x: 150, y: 100),
        ]
        #expect(CombatSlashGeometry.slashBisectsSquare(points: points, center: center, side: side))
    }

    @Test func diagonalThroughCutBisects() {
        let points = [
            CGPoint(x: 60, y: 60),
            CGPoint(x: 140, y: 140),
        ]
        #expect(CombatSlashGeometry.slashBisectsSquare(points: points, center: center, side: side))
    }

    @Test func multiPointPathThatCrossesBisects() {
        let points = [
            CGPoint(x: 100, y: 40),
            CGPoint(x: 100, y: 70),
            CGPoint(x: 100, y: 100),
            CGPoint(x: 100, y: 130),
            CGPoint(x: 100, y: 160),
        ]
        #expect(CombatSlashGeometry.slashBisectsSquare(points: points, center: center, side: side))
    }

    @Test func pokeIntoSameEdgeDoesNotBisect() {
        // Enter left edge, reverse back out the left edge.
        let points = [
            CGPoint(x: 50, y: 100),
            CGPoint(x: 90, y: 100),
            CGPoint(x: 50, y: 100),
        ]
        #expect(!CombatSlashGeometry.slashBisectsSquare(points: points, center: center, side: side))
    }

    @Test func grazeAlongOutsideDoesNotBisect() {
        let points = [
            CGPoint(x: 50, y: 100),
            CGPoint(x: 70, y: 100),
            CGPoint(x: 70, y: 140),
        ]
        #expect(!CombatSlashGeometry.slashBisectsSquare(points: points, center: center, side: side))
    }

    @Test func missFarAwayDoesNotBisect() {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 20, y: 20),
        ]
        #expect(!CombatSlashGeometry.slashBisectsSquare(points: points, center: center, side: side))
    }

    @Test func cornerToOppositeCornerBisects() {
        // Bottom → top via interior (distinct edges).
        let points = [
            CGPoint(x: 100, y: 50),
            CGPoint(x: 110, y: 100),
            CGPoint(x: 100, y: 150),
        ]
        #expect(CombatSlashGeometry.slashBisectsSquare(points: points, center: center, side: side))
    }
}
