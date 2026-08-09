import CoreGraphics
import Foundation
import Testing
@testable import Padawan_Adventures

@MainActor
private final class TutorialLog {
    var entries: [String] = []
}

@MainActor
private final class FakeTutorialStaging: WorldTutorialStaging {
    var spawnCoord: GridCoord
    var demoTarget: GridCoord?
    var isPlayerMoving = false
    var isInterrupted = false
    var interruptAfterBeginCamera = false
    let log: TutorialLog

    init(
        spawn: GridCoord = GridCoord(x: 0, y: 0, story: 0),
        demoTarget: GridCoord? = GridCoord(x: 3, y: 0, story: 0),
        log: TutorialLog
    ) {
        self.spawnCoord = spawn
        self.demoTarget = demoTarget
        self.log = log
    }

    func scenePoint(for coord: GridCoord) -> CGPoint {
        CGPoint(x: CGFloat(coord.x) * 10, y: CGFloat(coord.y) * 10)
    }

    func scenePoint(atViewFraction fraction: CGPoint) -> CGPoint {
        CGPoint(x: fraction.x * 100, y: fraction.y * 100)
    }

    func showTutorialChrome(cursorAt point: CGPoint, fadeSeconds: TimeInterval) async {
        log.entries.append("showChrome:\(Int(point.x)),\(Int(point.y))")
    }

    func hideTutorialChrome(fadeSeconds: TimeInterval) async {
        log.entries.append("hideChrome")
    }

    func speakIntro() {
        log.entries.append("speakIntro")
    }

    func beginCameraOwnership() {
        log.entries.append("beginCamera")
        if interruptAfterBeginCamera {
            isInterrupted = true
        }
    }

    func endCameraOwnership() {
        log.entries.append("endCamera")
    }

    func glideCameraToPlayer(duration: TimeInterval) async {
        log.entries.append("glideCamera")
    }
}

@MainActor
private final class FakeTutorialPerformer: MinigameDemoPerforming {
    private let log: TutorialLog
    private let leadInSeconds: TimeInterval
    private(set) var leadInPauseCount = 0

    init(log: TutorialLog, leadInSeconds: TimeInterval) {
        self.log = log
        self.leadInSeconds = leadInSeconds
    }

    func pause(_ seconds: TimeInterval) async {
        if abs(seconds - leadInSeconds) < 0.000_001 {
            leadInPauseCount += 1
            log.entries.append("leadIn")
        } else {
            log.entries.append("pause")
        }
    }

    func perform(_ move: MinigameDemoMove, gestureSeconds: TimeInterval) async {
        switch move.gesture {
        case let .tap(point):
            log.entries.append("tap:\(Int(point.x)),\(Int(point.y))")
        case let .drag(from, _):
            log.entries.append("drag:\(Int(from.x)),\(Int(from.y))")
        case .swipe:
            log.entries.append("swipe")
        }
    }
}

@MainActor
struct WorldTutorialScriptTests {
    private func fastTiming(maxLoops: Int = 2) -> WorldTutorialScript.Timing {
        WorldTutorialScript.Timing(
            settleSeconds: 0.001,
            fadeSeconds: 0.001,
            leadInSeconds: 0.002,
            beatSeconds: 0.001,
            dragSeconds: 0.001,
            panHoldSeconds: 0.001,
            cameraReturnSeconds: 0.001,
            movementStartTimeoutSeconds: 0.001,
            movementSettleTimeoutSeconds: 0.001,
            loopRestartSeconds: 0.001,
            maxLoops: maxLoops
        )
    }

    @Test func prologueRunsBeforeAnyGestureAndLeadInDoesNotRepeat() async {
        let log = TutorialLog()
        let staging = FakeTutorialStaging(log: log)
        let timing = fastTiming(maxLoops: 2)
        let performer = FakeTutorialPerformer(log: log, leadInSeconds: timing.leadInSeconds)
        let script = WorldTutorialScript(staging: staging, performer: performer, timing: timing)

        await script.run()

        let showIndex = log.entries.firstIndex(of: "showChrome:0,0")
        let speakIndex = log.entries.firstIndex(of: "speakIntro")
        let leadInIndex = log.entries.firstIndex(of: "leadIn")
        let firstGesture = log.entries.firstIndex(where: {
            $0.hasPrefix("tap:") || $0.hasPrefix("drag:")
        })
        #expect(showIndex != nil)
        #expect(speakIndex != nil)
        #expect(leadInIndex != nil)
        #expect(firstGesture != nil)
        if let showIndex, let speakIndex, let leadInIndex, let firstGesture {
            #expect(showIndex < speakIndex)
            #expect(speakIndex < leadInIndex)
            #expect(leadInIndex < firstGesture)
        }

        #expect(log.entries.filter { $0 == "speakIntro" }.count == 1)
        #expect(performer.leadInPauseCount == 1)
        #expect(log.entries.filter { $0.hasPrefix("showChrome") }.count == 1)
        #expect(log.entries.last == "hideChrome")
    }

    @Test func cycleOrderIsTapDragGlideTap() async {
        let log = TutorialLog()
        let staging = FakeTutorialStaging(log: log)
        let timing = fastTiming(maxLoops: 1)
        let performer = FakeTutorialPerformer(log: log, leadInSeconds: timing.leadInSeconds)
        let script = WorldTutorialScript(staging: staging, performer: performer, timing: timing)

        await script.run()

        let actions = log.entries.filter {
            $0.hasPrefix("tap:")
                || $0.hasPrefix("drag:")
                || $0 == "beginCamera"
                || $0 == "glideCamera"
                || $0 == "endCamera"
        }
        #expect(actions == [
            "tap:30,0",
            "beginCamera",
            "drag:30,30",
            "glideCamera",
            "endCamera",
            "tap:0,0",
        ])
    }

    @Test func loopsCycleBodyTwiceAndShowsChromeOnce() async {
        let log = TutorialLog()
        let staging = FakeTutorialStaging(log: log)
        let timing = fastTiming(maxLoops: 2)
        let performer = FakeTutorialPerformer(log: log, leadInSeconds: timing.leadInSeconds)
        let script = WorldTutorialScript(staging: staging, performer: performer, timing: timing)

        await script.run()

        #expect(log.entries.filter { $0.hasPrefix("showChrome") }.count == 1)
        #expect(log.entries.filter { $0 == "tap:30,0" }.count == 2)
        #expect(log.entries.filter { $0 == "tap:0,0" }.count == 2)
        #expect(log.entries.filter { $0 == "beginCamera" }.count == 2)
        #expect(log.entries.last == "hideChrome")
    }

    @Test func interruptionStopsMidCycle() async {
        let log = TutorialLog()
        let staging = FakeTutorialStaging(log: log)
        staging.interruptAfterBeginCamera = true
        let timing = fastTiming(maxLoops: 2)
        let performer = FakeTutorialPerformer(log: log, leadInSeconds: timing.leadInSeconds)
        let script = WorldTutorialScript(staging: staging, performer: performer, timing: timing)

        await script.run()

        #expect(log.entries.contains("beginCamera"))
        #expect(!log.entries.contains("glideCamera"))
        #expect(log.entries.filter { $0 == "tap:30,0" }.count == 1)
        #expect(log.entries.filter { $0 == "tap:0,0" }.isEmpty)
        #expect(log.entries.last == "hideChrome")
    }

    @Test func nilDemoTargetSkipsTapSteps() async {
        let log = TutorialLog()
        let staging = FakeTutorialStaging(demoTarget: nil, log: log)
        let timing = fastTiming(maxLoops: 2)
        let performer = FakeTutorialPerformer(log: log, leadInSeconds: timing.leadInSeconds)
        let script = WorldTutorialScript(staging: staging, performer: performer, timing: timing)

        await script.run()

        #expect(log.entries.contains("speakIntro"))
        #expect(log.entries.contains("leadIn"))
        #expect(log.entries.filter { $0.hasPrefix("tap:") }.isEmpty)
        #expect(log.entries.filter { $0.hasPrefix("drag:") }.isEmpty)
        #expect(log.entries.last == "hideChrome")
    }
}
