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

    @Test func sixChoiceRowFitsInsideChromeInsetsOnANarrowScene() {
        let scene = makeScene(
            size: CGSize(width: 500, height: 400),
            choiceCountMin: 6,
            choiceCountMax: 6
        )
        scene.buildContentForTesting()
        scene.layoutCurrentChoiceSet(fadeIn: false)

        #expect(scene.engine.currentChoices.count == 6)
        #expect(scene.choiceNodes.count == 6)

        let insets = scene.chromeInsets
        let bounds = CGRect(
            x: insets.left,
            y: 0,
            width: scene.size.width - insets.left - insets.right,
            height: scene.size.height
        )
        for node in scene.choiceNodes.values {
            let frame = node.calculateAccumulatedFrame()
            #expect(frame.minX >= bounds.minX - 0.5)
            #expect(frame.maxX <= bounds.maxX + 0.5)
            #expect(frame.minY >= bounds.minY - 0.5)
            #expect(frame.maxY <= bounds.maxY + 0.5)
        }
    }

    @Test func wideSceneKeepsPreferredCapacitorDiameterWhenSixFit() {
        let scene = makeScene(
            size: CGSize(width: 1600, height: 900),
            choiceCountMin: 6,
            choiceCountMax: 6
        )
        scene.buildContentForTesting()

        #expect(abs(scene.laidOutDiameter - scene.preferredCapacitorDiameter) < 0.01)
    }

    @Test func farRightDropIsValidAndPacksToLeaveRoom() throws {
        let scene = makeCatScene()
        scene.buildContentForTesting()
        #expect(scene.engine.targetGraphemes == ["c", "a", "t"])

        let index = try #require(scene.engine.currentIndex)
        let far = CGPoint(x: scene.maxDropX(forIndex: index), y: scene.playAreaRect.midY)
        #expect(scene.isValidDrop(far))

        try acceptCurrentAnswer(scene)
        scene.placedFractions = [CGPoint(x: 0.95, y: 0.5)]
        scene.rebuildLayout()

        #expect(scene.placedNodes.count == 1)
        let packed = scene.placedNodes[0].position
        #expect(scene.lastPlacedCenterFitsRemaining(packed.x))
        #expect(packed.x >= scene.playAreaRect.minX + scene.laidOutDiameter * 0.5 - 0.5)
    }

    @Test func packingDoesNotMoveWhenRemainingWidthIsEnough() throws {
        let scene = makeCatScene()
        scene.buildContentForTesting()
        try acceptCurrentAnswer(scene)
        scene.placedFractions = [CGPoint(x: 0.2, y: 0.5)]
        scene.rebuildLayout()

        let expected = CGPoint(
            x: scene.playAreaRect.minX + scene.playAreaRect.width * 0.2,
            y: scene.playAreaRect.minY + scene.playAreaRect.height * 0.5
        )
        #expect(scene.placedNodes.count == 1)
        #expect(abs(scene.placedNodes[0].position.x - expected.x) < 0.5)
        #expect(abs(scene.placedNodes[0].position.y - expected.y) < 0.5)
        #expect(scene.lastPlacedCenterFitsRemaining(scene.placedNodes[0].position.x))
    }

    @Test func lastLetterDoesNotShift() throws {
        let scene = makeCatScene()
        scene.buildContentForTesting()
        try acceptCurrentAnswer(scene)
        try acceptCurrentAnswer(scene)
        try acceptCurrentAnswer(scene)
        #expect(scene.engine.isSolved)

        scene.placedFractions = [
            CGPoint(x: 0.2, y: 0.4),
            CGPoint(x: 0.5, y: 0.5),
            CGPoint(x: 0.95, y: 0.6),
        ]
        scene.rebuildLayout()

        let last = scene.placedNodes[2].position
        let expectedX = scene.playAreaRect.minX + scene.playAreaRect.width * 0.95
        let expectedY = scene.playAreaRect.minY + scene.playAreaRect.height * 0.6
        #expect(abs(last.x - expectedX) < 0.5)
        #expect(abs(last.y - expectedY) < 0.5)
    }

    @Test func leftWallPacksXAndKeepsY() throws {
        let scene = makeCatScene()
        scene.buildContentForTesting()
        try acceptCurrentAnswer(scene)
        try acceptCurrentAnswer(scene)
        #expect(scene.engine.placedCount == 2)

        let rect = scene.playAreaRect
        let radius = scene.laidOutDiameter * 0.5
        let first = CGPoint(x: rect.minX + radius, y: rect.minY + rect.height * 0.35)
        let last = CGPoint(x: rect.maxX - radius, y: rect.minY + rect.height * 0.7)
        scene.placedFractions = [
            scene.playAreaFraction(of: first),
            scene.playAreaFraction(of: last),
        ]
        scene.rebuildLayout()

        let minFirstX = rect.minX + radius
        #expect(scene.placedNodes.count == 2)
        #expect(abs(scene.placedNodes[0].position.x - minFirstX) < 0.5)
        #expect(abs(scene.placedNodes[1].position.x - (minFirstX + scene.minCenterDistance)) < 0.5)
        #expect(abs(scene.placedNodes[0].position.y - first.y) < 0.5)
        #expect(abs(scene.placedNodes[1].position.y - last.y) < 0.5)
        #expect(scene.lastPlacedCenterFitsRemaining(scene.placedNodes[1].position.x))
    }

    @Test func assistRejectedForSmallNudgeTowardPlayArea() throws {
        let scene = makeCatScene()
        scene.buildContentForTesting()
        scene.layoutCurrentChoiceSet(fadeIn: false)
        let home = try #require(scene.choiceHome.values.first)
        let nudge = CGPoint(x: home.x, y: home.y + 12)
        #expect(!scene.shouldAssistPlacement(fromHome: home, at: nudge))
    }

    @Test func assistAcceptedAfterEnoughTravelTowardPlayArea() throws {
        let scene = makeCatScene()
        scene.buildContentForTesting()
        scene.layoutCurrentChoiceSet(fadeIn: false)
        let home = try #require(scene.choiceHome.values.first)
        let threshold = scene.assistTravelThreshold(fromHome: home)
        let far = CGPoint(x: home.x, y: home.y + threshold + 5)
        #expect(scene.shouldAssistPlacement(fromHome: home, at: far))
    }

    @Test func placedHitTestAndClampStayInPlayArea() throws {
        let scene = makeCatScene()
        scene.buildContentForTesting()
        try acceptCurrentAnswer(scene)
        scene.placedFractions = [CGPoint(x: 0.3, y: 0.5)]
        scene.rebuildLayout()

        let node = try #require(scene.placedNodes.first)
        #expect(scene.placedIndex(at: node.position) == 0)
        #expect(scene.placedIndex(at: .zero) == nil)

        let outside = CGPoint(
            x: scene.playAreaRect.maxX + 200,
            y: scene.playAreaRect.maxY + 200
        )
        let clamped = scene.clampedPlacedPosition(outside, forIndex: 0)
        let radius = scene.laidOutDiameter * 0.5
        let vertical = scene.playAreaVerticalCenterLimits
        #expect(clamped.x <= scene.playAreaRect.maxX - radius + 0.5)
        #expect(clamped.x >= scene.playAreaRect.minX + radius - 0.5)
        #expect(clamped.y <= min(vertical.maxY, scene.maxPlayableCenterY(for: radius)) + 0.5)
        #expect(clamped.y >= vertical.minY - 0.5)
    }

    @Test func placedClampKeepsNeighbourSpacingAndCommitUpdatesFractions() throws {
        let scene = makeCatScene()
        scene.buildContentForTesting()
        try acceptCurrentAnswer(scene)
        try acceptCurrentAnswer(scene)

        let rect = scene.playAreaRect
        let radius = scene.laidOutDiameter * 0.5
        let first = CGPoint(x: rect.minX + radius, y: rect.midY)
        let second = CGPoint(x: first.x + scene.minCenterDistance * 2, y: rect.midY)
        scene.placedFractions = [
            scene.playAreaFraction(of: first),
            scene.playAreaFraction(of: second),
        ]
        scene.rebuildLayout()

        let rightNeighbour = scene.placedNodes[1].position.x
        let pushed = scene.clampedPlacedPosition(
            CGPoint(x: rightNeighbour + 80, y: scene.placedNodes[0].position.y),
            forIndex: 0
        )
        #expect(pushed.x <= rightNeighbour - scene.minCenterDistance + 0.5)

        scene.placedNodes[1].position = CGPoint(
            x: scene.playAreaRect.maxX - radius,
            y: scene.playAreaRect.midY
        )
        scene.applyPlacedPositionsFittingRemaining(animated: false)
        #expect(scene.lastPlacedCenterFitsRemaining(scene.placedNodes[1].position.x))
        let expected = scene.playAreaFraction(of: scene.placedNodes[1].position)
        #expect(abs(scene.placedFractions[1].x - expected.x) < 0.001)
        #expect(abs(scene.placedFractions[1].y - expected.y) < 0.001)
    }

    private func makeScene(
        size: CGSize = CGSize(width: 800, height: 600),
        choiceCountMin: Int? = nil,
        choiceCountMax: Int? = nil
    ) -> GateSoundOutWordScene {
        let puzzleConfig: GateSoundOutWordConfig
        if let choiceCountMin, let choiceCountMax {
            puzzleConfig = GateSoundOutWordConfig(
                choiceCountMin: choiceCountMin,
                choiceCountMax: choiceCountMax,
                words: WordCatalog.fallback.words,
                graphemes: GraphemeCatalog.fallback.graphemes
            )
        } else {
            puzzleConfig = .fallback
        }
        return GateSoundOutWordScene(size: size, puzzleConfig: puzzleConfig)
    }

    private func makeCatScene() -> GateSoundOutWordScene {
        let alphabet = "abcdefghijklmnopqrstuvwxyz".map(String.init)
        let graphemes = alphabet.map {
            GateGrapheme(
                grapheme: $0,
                pronunciation: "sfx_letter_\($0)",
                name: "sfx_letter_\($0)_name"
            )
        }
        return GateSoundOutWordScene(
            size: CGSize(width: 800, height: 600),
            puzzleConfig: GateSoundOutWordConfig(
                words: [GateWord.fallbackEntry(word: "cat")],
                graphemes: graphemes
            )
        )
    }

    private func acceptCurrentAnswer(_ scene: GateSoundOutWordScene) throws {
        let answer = try #require(
            scene.engine.currentChoices.first { $0.grapheme == scene.engine.currentGrapheme }
        )
        #expect(scene.engine.drop(choiceID: answer.id, isPlacementValid: true) == .accepted)
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
