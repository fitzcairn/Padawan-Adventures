import CoreGraphics
import SpriteKit
import Testing
import UIKit
@testable import Padawan_Adventures

@MainActor
struct PitSoundOutWordSceneTests {
    @Test func promptLettersStartWhite() {
        let scene = makeScene()
        scene.buildContentForTesting()
        #expect(!scene.wordGraphemeNodes.isEmpty)
        for index in scene.wordGraphemeNodes.indices {
            #expect(colorsMatch(promptFill(scene, at: index), scene.promptPendingColor))
        }
    }

    @Test func placedPromptLettersStayGreen() throws {
        let scene = makeScene()
        scene.buildContentForTesting()
        #expect(scene.engine.targetGraphemes.count >= 2)

        let answer = try #require(
            scene.engine.currentChoices.first { $0.grapheme == scene.engine.currentGrapheme }
        )
        #expect(scene.engine.drop(choiceID: answer.id, isPlacementValid: true) == .accepted)
        scene.updatePromptColors()

        #expect(colorsMatch(promptFill(scene, at: 0), scene.promptPlacedColor))
        for index in 1..<scene.wordGraphemeNodes.count {
            #expect(colorsMatch(promptFill(scene, at: index), scene.promptPendingColor))
        }
    }

    private func makeScene() -> PitSoundOutWordScene {
        PitSoundOutWordScene(
            size: CGSize(width: 390, height: 844),
            soundOutConfig: .fallback,
            pitFx: .empty,
            floorTileSetLibrary: FloorTileSetLibrary(),
            isoConfig: IsometricConfig(),
            spriteLibrary: SpriteLibrary(),
            playerSpriteConfig: nil
        )
    }

    private func promptFill(_ scene: PitSoundOutWordScene, at index: Int) -> UIColor? {
        OutlinedLetterFactory.fillLabel(in: scene.wordGraphemeNodes[index])?.fontColor
    }

    /// SpriteKit stores fills in sRGB, so `UIColor.white` fails `==`.
    private func colorsMatch(_ lhs: UIColor?, _ rhs: UIColor) -> Bool {
        guard let lhs, let a = sRGB(lhs), let b = sRGB(rhs) else { return false }
        return abs(a.r - b.r) < 0.02
            && abs(a.g - b.g) < 0.02
            && abs(a.b - b.b) < 0.02
            && abs(a.a - b.a) < 0.02
    }

    private func sRGB(_ color: UIColor) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)? {
        let resolved = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let label = SKLabelNode()
        label.fontColor = resolved
        guard let stored = label.fontColor,
              let converted = stored.cgColor.converted(
                to: CGColorSpaceCreateDeviceRGB(),
                intent: .defaultIntent,
                options: nil
              ),
              let components = converted.components,
              components.count >= 3 else {
            return nil
        }
        return (
            components[0],
            components[1],
            components[2],
            components.count > 3 ? components[3] : 1
        )
    }
}
