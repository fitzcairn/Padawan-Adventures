import CoreGraphics
import SpriteKit
import Testing
import UIKit
@testable import Padawan_Adventures

@MainActor
struct EffectsHelpersTests {
    @Test func makeGlowStrokeAppliesRoundedAntialiasedStroke() {
        let path = CGMutablePath()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: 10, y: 0))
        let node = makeGlowStroke(
            path: path,
            lineWidth: 4,
            color: .cyan,
            glowWidth: 2
        )
        #expect(node.lineWidth == 4)
        #expect(node.glowWidth == 2)
        #expect(node.lineCap == .round)
        #expect(node.lineJoin == .round)
        #expect(node.isAntialiased == true)
        #expect(node.fillColor.cgColor.alpha == 0)
    }

    @Test func doubleFlashHasExpectedDuration() {
        let action = SKAction.doubleFlash(period: 0.12, count: 2, apply: {}, clear: {})
        #expect(abs(action.duration - 0.48) < 0.000_1)
    }

    @Test func goldSparkleParticleImageIsCached() {
        let a = GoldSparkleEmitter.makeLayer(side: 40, position: .zero)
        let b = GoldSparkleEmitter.makeLayer(side: 40, position: .zero)
        let contentsA = a.emitterCells?.first?.contents
        let contentsB = b.emitterCells?.first?.contents
        #expect(contentsA != nil)
        #expect(contentsB != nil)
        // Same cached CGImage instance (AnyObject identity).
        #expect((contentsA as AnyObject) === (contentsB as AnyObject))
    }
}
