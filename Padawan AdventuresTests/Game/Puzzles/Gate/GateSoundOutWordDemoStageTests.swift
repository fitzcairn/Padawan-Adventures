import CoreGraphics
import SpriteKit
import Testing
@testable import Padawan_Adventures

@MainActor
struct GateSoundOutWordDemoStageTests {
    @Test func demoChoiceTapsMatchEngineOrderAndHomes() {
        let scene = GateSoundOutWordScene(
            size: CGSize(width: 800, height: 600),
            puzzleConfig: .fallback
        )
        scene.buildContentForTesting()
        // `beginRound` leaves input locked until SKActions fire; lay the set out
        // directly so the stage can be inspected without a presented SKView.
        scene.layoutCurrentChoiceSet(fadeIn: false)

        let taps = scene.demoChoiceTaps
        #expect(taps.count == scene.engine.currentChoices.count)
        #expect(taps.count == scene.choiceHome.count)

        for (index, choice) in scene.engine.currentChoices.enumerated() {
            guard let home = scene.choiceHome[choice.id] else {
                Issue.record("missing home for choice \(index)")
                continue
            }
            #expect(abs(taps[index].point.x - home.x) < 0.001)
            #expect(abs(taps[index].point.y - home.y) < 0.001)
        }

        #expect(scene.demoCorrectMove != nil)
        #expect(scene.demoWrongMove != nil)
        #expect(scene.demoScript != nil)

        // Drops use the leftmost legal slot so arcs chain left-to-right.
        guard let index = scene.engine.currentIndex,
              case let .drag(_, drop)? = scene.demoCorrectMove?.gesture else {
            Issue.record("expected correct drag move")
            return
        }
        #expect(abs(drop.x - scene.minDropX(forIndex: index)) < 0.5)
        #expect(abs(drop.y - scene.playAreaRect.midY) < 0.5)
    }

    @Test func demoRestartPreservesOverlaysAndClearsPlacement() {
        let scene = GateSoundOutWordScene(
            size: CGSize(width: 800, height: 600),
            puzzleConfig: .fallback
        )
        scene.buildContentForTesting()
        scene.layoutCurrentChoiceSet(fadeIn: false)

        let cursor = SKNode()
        cursor.name = "demoCursor"
        scene.addChild(cursor)
        let coins = MinigameDemoCoinLayer(scene: scene)

        scene.placedFractions = [CGPoint(x: 0.2, y: 0.5)]
        scene.didEnd = true
        scene.isCompletingWin = true
        scene.isUserInteractionEnabled = false

        scene.demoRestart()

        #expect(scene.childNode(withName: "demoCursor") === cursor)
        #expect(scene.childNode(withName: MinigameDemoCoinLayer.rootName) != nil)
        #expect(scene.placedNodes.isEmpty)
        #expect(scene.placedFractions.isEmpty)
        #expect(scene.didEnd == false)
        #expect(scene.isCompletingWin == false)
        #expect(scene.isUserInteractionEnabled == true)

        coins.teardown()
    }
}
