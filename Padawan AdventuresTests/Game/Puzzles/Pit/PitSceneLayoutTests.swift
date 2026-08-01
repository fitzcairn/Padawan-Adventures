import CoreGraphics
import SpriteKit
import Testing
@testable import Padawan_Adventures

@MainActor
struct PitSceneLayoutTests {
    private func words(_ values: [String]) -> [GateWord] {
        values.map { GateWord.fallbackEntry(word: $0) }
    }

    private func makeScene(
        size: CGSize,
        words: [String],
        numPaddingLetters: Int = 12
    ) -> PitScene {
        PitScene(
            size: size,
            puzzleConfig: PitPuzzleConfig(
                numPaddingLetters: numPaddingLetters,
                words: self.words(words)
            ),
            pitFx: .empty,
            playerFx: .empty,
            pitSpriteSetLibrary: PitSpriteSetLibrary(),
            floorTileSetLibrary: FloorTileSetLibrary(),
            isoConfig: IsometricConfig(),
            spriteLibrary: SpriteLibrary(),
            playerSpriteConfig: nil
        )
    }

    @Test func degenerateLayoutStillCreatesPlayerAndAcceptsTouch() {
        let scene = makeScene(
            size: CGSize(width: 320, height: 240),
            words: ["extraordinary"]
        )
        let view = SKView(frame: CGRect(origin: .zero, size: scene.size))
        view.presentScene(scene)

        #expect(scene.childNode(withName: "player") != nil)

        scene.touchesBeganForTesting(at: CGPoint(x: scene.size.width * 0.5, y: scene.size.height * 0.5))
        if let letter = scene.children.first(where: { $0.name?.hasPrefix("letter:") == true }) {
            scene.touchesBeganForTesting(at: letter.position)
        }
    }
}
