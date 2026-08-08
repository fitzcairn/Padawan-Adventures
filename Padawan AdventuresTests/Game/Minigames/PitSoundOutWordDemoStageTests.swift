import CoreGraphics
import SpriteKit
import Testing
@testable import Padawan_Adventures

@MainActor
struct PitSoundOutWordDemoStageTests {
    @Test func demoMovesContainExactlyOneCorrectWithinBounds() {
        let scene = PitSoundOutWordScene(
            size: CGSize(width: 390, height: 844),
            soundOutConfig: .fallback,
            pitFx: .empty,
            floorTileSetLibrary: FloorTileSetLibrary(),
            isoConfig: IsometricConfig(),
            spriteLibrary: SpriteLibrary(),
            playerSpriteConfig: nil
        )
        scene.buildContentForTesting()
        // Word-sound gating uses SKActions that need a running SKView; drive the
        // first step directly so the stage can be inspected.
        scene.beginStep()

        #expect(scene.demoAcceptsInput)
        let moves = scene.demoMoves
        #expect(!moves.isEmpty)
        #expect(moves.filter(\.isCorrect).count == 1)
        #expect(moves.contains(where: { !$0.isCorrect }))

        let minDrag = scene.geometry.tileSide * 0.35
        for move in moves {
            guard case let .drag(from, to) = move.gesture else {
                Issue.record("expected drag gesture")
                continue
            }
            #expect(from.x >= 0 && from.x <= scene.size.width)
            #expect(from.y >= 0 && from.y <= scene.size.height)
            #expect(to.x >= 0 && to.x <= scene.size.width)
            #expect(to.y >= 0 && to.y <= scene.size.height)
            #expect(hypot(to.x - from.x, to.y - from.y) > minDrag)
        }
    }
}
