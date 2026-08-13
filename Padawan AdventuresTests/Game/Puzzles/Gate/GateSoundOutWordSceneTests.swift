import CoreGraphics
import SpriteKit
import Testing
import UIKit
@testable import Padawan_Adventures

@MainActor
struct GateSoundOutWordSceneTests {
    @Test func promptLettersStartWhite() {
        let scene = makeScene()
        scene.buildContentForTesting()
        #expect(!scene.promptLetterNodes.isEmpty)
        for index in scene.promptLetterNodes.indices {
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
        for index in 1..<scene.promptLetterNodes.count {
            #expect(colorsMatch(promptFill(scene, at: index), scene.promptPendingColor))
        }
    }

    @Test func restoreProgressKeepsPlacedLettersGreenAndCurrentOrange() throws {
        let scene = makeScene()
        scene.buildContentForTesting()
        #expect(scene.engine.targetGraphemes.count >= 2)

        let answer = try #require(
            scene.engine.currentChoices.first { $0.grapheme == scene.engine.currentGrapheme }
        )
        #expect(scene.engine.drop(choiceID: answer.id, isPlacementValid: true) == .accepted)
        scene.placedFractions = [CGPoint(x: 0.2, y: 0.5)]
        scene.rebuildLayout()

        #expect(colorsMatch(promptFill(scene, at: 0), scene.promptPlacedColor))
        #expect(colorsMatch(promptFill(scene, at: 1), scene.promptActiveColor))
        for index in 2..<scene.promptLetterNodes.count {
            #expect(colorsMatch(promptFill(scene, at: index), scene.promptPendingColor))
        }
    }

    private func makeScene() -> GateSoundOutWordScene {
        GateSoundOutWordScene(
            size: CGSize(width: 800, height: 600),
            puzzleConfig: .fallback
        )
    }

    private func promptFill(_ scene: GateSoundOutWordScene, at index: Int) -> UIColor? {
        OutlinedLetterFactory.fillLabel(in: scene.promptLetterNodes[index])?.fontColor
    }

    /// SpriteKit stores fills in sRGB, so `UIColor.white` / `.systemOrange` fail `==`.
    private func colorsMatch(_ lhs: UIColor?, _ rhs: UIColor) -> Bool {
        guard let lhs, let a = sRGB(lhs), let b = sRGB(rhs) else { return false }
        return abs(a.r - b.r) < 0.02
            && abs(a.g - b.g) < 0.02
            && abs(a.b - b.b) < 0.02
            && abs(a.a - b.a) < 0.02
    }

    private func sRGB(_ color: UIColor) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)? {
        let label = SKLabelNode()
        label.fontColor = color
        let stored = label.fontColor ?? color
        if let components = rgbComponents(stored) { return components }
        let resolved = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        return rgbComponents(resolved)
    }

    private func rgbComponents(_ color: UIColor) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if color.getRed(&r, green: &g, blue: &b, alpha: &a) {
            return (r, g, b, a)
        }
        guard let converted = color.cgColor.converted(
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
