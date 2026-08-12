import CoreGraphics
import Foundation
import SpriteKit
import Testing
@testable import Padawan_Adventures

@MainActor
final class FakePitBridgeStaging: PitBridgeDemoStaging {
    struct Phase {
        var wrong: MinigameDemoMove?
        var correct: MinigameDemoMove?
    }

    /// Tile-1 then tile-2 phases for one demo cycle.
    private let phases: [Phase]
    private var phaseIndex = 0
    private(set) var restartCount = 0
    var isReady = true
    var isOver = false
    /// When true, `demoIsReady` stays false so `waitUntilReady` times out.
    var neverReady = false
    /// After this many restarts, mark the stage over so the forever loop can exit
    /// without relying solely on cooperative cancellation.
    var stopAfterRestarts: Int?

    init(phases: [Phase]) {
        self.phases = phases
    }

    private var current: Phase? {
        guard phaseIndex < phases.count else { return nil }
        return phases[phaseIndex]
    }

    var demoIsReady: Bool {
        !neverReady && isReady && !isOver && current?.correct != nil
    }

    var demoIsOver: Bool { isOver }

    var demoWrongMove: MinigameDemoMove? { current?.wrong }
    var demoCorrectMove: MinigameDemoMove? { current?.correct }

    func demoRestart() {
        restartCount += 1
        if let stopAfterRestarts, restartCount >= stopAfterRestarts {
            isOver = true
            isReady = false
            return
        }
        isOver = false
        isReady = true
        phaseIndex = 0
    }

    func markAfterCorrect() {
        if phaseIndex + 1 < phases.count {
            phaseIndex += 1
            return
        }
        // Last correct ends the cycle; script calls demoRestart next.
        isReady = false
    }
}

@MainActor
final class RecordingPitBridgePerformer: MinigameDemoPerforming {
    private let stage: FakePitBridgeStaging
    private(set) var gestures: [MinigameDemoMove.Gesture] = []
    private(set) var pauseDurations: [TimeInterval] = []

    init(stage: FakePitBridgeStaging) {
        self.stage = stage
    }

    func pause(_ seconds: TimeInterval) async {
        pauseDurations.append(seconds)
        // Must actually suspend: a no-op pause lets the forever demo loop pin the
        // MainActor and deadlocks any test that tries to cancel it.
        try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }

    func perform(_ move: MinigameDemoMove, gestureSeconds _: TimeInterval) async {
        gestures.append(move.gesture)
        if move.isCorrect {
            stage.markAfterCorrect()
        } else {
            stage.isReady = true
        }
    }
}

@MainActor
struct PitBridgeDemoScriptTests {
    private func makeDrag(from: CGPoint, to: CGPoint, isCorrect: Bool) -> MinigameDemoMove {
        MinigameDemoMove(
            gesture: .drag(from: from, to: to),
            isCorrect: isCorrect,
            coinAnchor: to
        )
    }

    private func fastTiming() -> PitBridgeDemoScript.Timing {
        var timing = PitBridgeDemoScript.Timing()
        timing.gestureSeconds = 0.01
        timing.beatSeconds = 0.01
        timing.settleSeconds = 0.01
        timing.holdSeconds = 0.01
        timing.pollSeconds = 0.01
        timing.readyTimeoutSeconds = 2
        return timing
    }

    private func twoTilePhases() -> [FakePitBridgeStaging.Phase] {
        let slot1 = CGPoint(x: 100, y: 200)
        let slot2 = CGPoint(x: 200, y: 200)
        return [
            .init(
                wrong: nil,
                correct: makeDrag(from: CGPoint(x: 50, y: 40), to: slot1, isCorrect: true)
            ),
            .init(
                wrong: makeDrag(from: CGPoint(x: 30, y: 40), to: slot2, isCorrect: false),
                correct: makeDrag(from: CGPoint(x: 70, y: 40), to: slot2, isCorrect: true)
            ),
        ]
    }

    @Test func firstCycleGestureOrderAndCoinFlights() async {
        let stage = FakePitBridgeStaging(phases: twoTilePhases())
        stage.stopAfterRestarts = 1
        let performer = RecordingPitBridgePerformer(stage: stage)
        var coinAnchors: [CGPoint] = []
        let script = PitBridgeDemoScript(stage: stage, timing: fastTiming())

        await script.run(performer: performer) { point in
            coinAnchors.append(point)
            stage.isReady = true
        }

        #expect(performer.gestures.count >= 3)

        guard case let .drag(_, firstTo)? = performer.gestures[optional: 0] else {
            Issue.record("expected correct first-tile drag")
            return
        }
        #expect(firstTo == CGPoint(x: 100, y: 200))

        guard case let .drag(_, wrongTo)? = performer.gestures[optional: 1] else {
            Issue.record("expected wrong second-tile drag")
            return
        }
        #expect(wrongTo == CGPoint(x: 200, y: 200))

        guard case let .drag(_, secondTo)? = performer.gestures[optional: 2] else {
            Issue.record("expected correct second-tile drag")
            return
        }
        #expect(secondTo == CGPoint(x: 200, y: 200))

        #expect(coinAnchors.count >= 2)
        #expect(coinAnchors[optional: 0] == CGPoint(x: 100, y: 200))
        #expect(coinAnchors[optional: 1] == CGPoint(x: 200, y: 200))
        #expect(stage.restartCount >= 1)
    }

    @Test func restartBeginsSecondCycle() async {
        let stage = FakePitBridgeStaging(phases: twoTilePhases())
        stage.stopAfterRestarts = 2
        let performer = RecordingPitBridgePerformer(stage: stage)
        var coinCount = 0
        let script = PitBridgeDemoScript(stage: stage, timing: fastTiming())

        await script.run(performer: performer) { _ in
            coinCount += 1
            stage.isReady = true
        }

        #expect(stage.restartCount >= 2)
        #expect(coinCount >= 4)
        // Two full cycles: correct, wrong, correct, then again.
        #expect(performer.gestures.count >= 6)
    }

    @Test func continueCueRunsBeforeTheRestart() async {
        let stage = FakePitBridgeStaging(phases: twoTilePhases())
        stage.stopAfterRestarts = 1
        let performer = RecordingPitBridgePerformer(stage: stage)
        var restartCountsAtCue: [Int] = []
        let script = PitBridgeDemoScript(stage: stage, timing: fastTiming())

        await script.run(performer: performer) { _ in
            stage.isReady = true
        } onLoopBoundary: {
            restartCountsAtCue.append(stage.restartCount)
        }

        // One cue per finished pass, played while the finished bridge is still up.
        #expect(restartCountsAtCue == [0])
    }

    @Test func neverReadyStageRestartsInsteadOfReturning() async {
        let stage = FakePitBridgeStaging(phases: twoTilePhases())
        stage.neverReady = true
        stage.stopAfterRestarts = 1
        let performer = RecordingPitBridgePerformer(stage: stage)
        var timing = fastTiming()
        timing.readyTimeoutSeconds = 0.05
        let script = PitBridgeDemoScript(stage: stage, timing: timing)

        await script.run(performer: performer) { _ in }

        #expect(stage.restartCount >= 1)
        #expect(performer.gestures.isEmpty)
    }

    @Test func cancellingTaskEndsLoop() async {
        let stage = FakePitBridgeStaging(phases: twoTilePhases())
        let performer = RecordingPitBridgePerformer(stage: stage)
        var timing = fastTiming()
        timing.readyTimeoutSeconds = 2
        let script = PitBridgeDemoScript(stage: stage, timing: timing)

        let task = Task { @MainActor in
            await script.run(performer: performer) { _ in
                stage.isReady = true
            }
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        await task.value
        #expect(task.isCancelled)
    }
}

@MainActor
struct PitBridgeDemoStageTests {
    @Test func demoScriptIsWiredAndMovesArePresent() {
        let scene = makeScene()
        scene.buildContentForTesting()
        // `beginRound` waits on SKActions for the word cue; reveal the tray directly.
        scene.revealTray()

        #expect(scene.demoScript != nil)
        #expect(scene.demoCorrectMove != nil)
        #expect(scene.demoWrongMove != nil)
        #expect(scene.demoAcceptsInput)
    }

    @Test func demoRestartPreservesOverlaysAndClearsPlacement() {
        let scene = makeScene()
        scene.buildContentForTesting()
        scene.revealTray()

        let cursor = SKNode()
        cursor.name = "demoCursor"
        scene.addChild(cursor)
        let coins = MinigameDemoCoinLayer(scene: scene)

        // Simulate a placed tile so restart has something to clear.
        if let first = scene.trayNodes.values.first {
            scene.placedTileNodes.append(first)
        }
        scene.didEnd = true
        scene.isJumping = true
        scene.isUserInteractionEnabled = false

        scene.demoRestart()
        // Word-cue gating uses SKActions; reveal the tray the same way the live
        // scene would once the prompt finishes.
        scene.revealTray()

        #expect(scene.childNode(withName: "demoCursor") === cursor)
        #expect(scene.childNode(withName: MinigameDemoCoinLayer.rootName) != nil)
        #expect(scene.placedTileNodes.isEmpty)
        #expect(scene.didEnd == false)
        #expect(scene.isJumping == false)
        #expect(scene.isUserInteractionEnabled == true)
        #expect(scene.engine.roundIndex == 0)
        #expect(scene.demoAcceptsInput)

        coins.teardown()
    }

    @Test func tapOnTrayTileLeavesItInPlace() {
        let scene = makeScene()
        scene.buildContentForTesting()
        scene.revealTray()

        guard let node = scene.trayNodes.values.first else {
            Issue.record("expected a tray tile")
            return
        }
        let home = node.position
        let round = scene.engine.roundIndex

        scene.beginChoiceTouchForTesting(on: node)
        scene.endDrag()

        #expect(node.position == home)
        #expect(scene.draggedNode == nil)
        #expect(scene.dragMoved == false)
        #expect(scene.engine.roundIndex == round)
        #expect(node.action(forKey: PitBridgeScene.snapIntoSlotActionKey) == nil)
        #expect(scene.isUserInteractionEnabled)
    }

    @Test func dragAssistSnapsOnlyAfterApproachingTheSlot() {
        let scene = makeScene()
        scene.buildContentForTesting()
        scene.revealTray()

        guard let node = scene.trayNodes.values.first else {
            Issue.record("expected a tray tile")
            return
        }
        let home = node.position
        let slot = scene.geometry.slotCenter(scene.engine.roundIndex)
        let nearSlot = CGPoint(
            x: slot.x + scene.geometry.tileSide * 0.4,
            y: slot.y
        )

        scene.beginChoiceTouchForTesting(on: node)
        // Stay under the tap threshold — still a tap, even if the tile's rest
        // position sits inside the drop radius.
        scene.handleTouchMoved(at: CGPoint(x: home.x + 4, y: home.y))
        scene.endDrag()
        #expect(node.position == home)
        #expect(scene.engine.roundIndex == 0)
        #expect(scene.isUserInteractionEnabled)

        scene.beginChoiceTouchForTesting(on: node)
        scene.handleTouchMoved(at: CGPoint(x: home.x, y: home.y + scene.tapMoveThreshold + 1))
        scene.handleTouchMoved(at: nearSlot)
        scene.endDrag()

        #expect(scene.isUserInteractionEnabled == false)
        #expect(
            node.action(forKey: PitBridgeScene.snapIntoSlotActionKey) != nil
                || hypot(node.position.x - slot.x, node.position.y - slot.y) < 1
        )
    }

    private func makeScene() -> PitBridgeScene {
        PitBridgeScene(
            size: CGSize(width: 800, height: 600),
            bridgeConfig: .fallback,
            pitFx: .empty,
            playerFx: .empty,
            floorTileSetLibrary: FloorTileSetLibrary(),
            isoConfig: IsometricConfig(),
            spriteLibrary: SpriteLibrary(),
            playerSpriteConfig: nil
        )
    }
}

private extension Array {
    subscript(optional index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
