import CoreGraphics
import SpriteKit
import Testing
@testable import Padawan_Adventures

@MainActor
struct GateGraphemeMatchDemoStageTests {
    @Test func coinAnchorsSpawnAtScreenCenter() {
        let size = CGSize(width: 800, height: 600)
        let scene = GateGraphemeMatchScene(
            size: size,
            puzzleConfig: .fallback
        )
        scene.buildContentForTesting()

        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        #expect(scene.demoCoinAnchor == center)

        let moves = scene.demoMoves
        #expect(!moves.isEmpty)
        for move in moves {
            #expect(move.coinAnchor == center)
        }
    }
}
