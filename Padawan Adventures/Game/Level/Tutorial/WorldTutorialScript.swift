import CoreGraphics
import Foundation

/// Abstraction over the world scene so unit tests can drive the tutorial without SpriteKit.
@MainActor
protocol WorldTutorialStaging: AnyObject {
    var spawnCoord: GridCoord { get }
    var demoTarget: GridCoord? { get }
    var isPlayerMoving: Bool { get }
    /// True once an encounter overlay has taken over; the script must stop.
    var isInterrupted: Bool { get }

    func scenePoint(for coord: GridCoord) -> CGPoint
    /// `fraction` is measured from the view's top-left, e.g. (0.3, 0.3).
    func scenePoint(atViewFraction fraction: CGPoint) -> CGPoint
    /// Fades in the hand cursor and the "Tap to continue" hint together.
    func showTutorialChrome(cursorAt point: CGPoint, fadeSeconds: TimeInterval) async
    func hideTutorialChrome(fadeSeconds: TimeInterval) async
    func speakIntro()
    func beginCameraOwnership()
    func endCameraOwnership()
    func glideCameraToPlayer(duration: TimeInterval) async
}

/// Once-only prologue + repeating tap/drag demonstration for the level-1 world tutorial.
@MainActor
final class WorldTutorialScript {
    /// Value type kept `nonisolated` so it can be used as a default argument.
    nonisolated struct Timing: Sendable {
        var settleSeconds: TimeInterval = 0.8
        var fadeSeconds: TimeInterval = 0.3
        /// Prologue only — hold still while the voiceover plays.
        var leadInSeconds: TimeInterval = 3.0
        var beatSeconds: TimeInterval = 1.0
        var dragSeconds: TimeInterval = 1.0
        var panHoldSeconds: TimeInterval = 0.6
        var cameraReturnSeconds: TimeInterval = 0.7
        var movementStartTimeoutSeconds: TimeInterval = 1.5
        var movementSettleTimeoutSeconds: TimeInterval = 6.0
        var loopRestartSeconds: TimeInterval = 1.2
        var maxLoops: Int = 5

        nonisolated init(
            settleSeconds: TimeInterval = 0.8,
            fadeSeconds: TimeInterval = 0.3,
            leadInSeconds: TimeInterval = 3.0,
            beatSeconds: TimeInterval = 1.0,
            dragSeconds: TimeInterval = 1.0,
            panHoldSeconds: TimeInterval = 0.6,
            cameraReturnSeconds: TimeInterval = 0.7,
            movementStartTimeoutSeconds: TimeInterval = 1.5,
            movementSettleTimeoutSeconds: TimeInterval = 6.0,
            loopRestartSeconds: TimeInterval = 1.2,
            maxLoops: Int = 5
        ) {
            self.settleSeconds = settleSeconds
            self.fadeSeconds = fadeSeconds
            self.leadInSeconds = leadInSeconds
            self.beatSeconds = beatSeconds
            self.dragSeconds = dragSeconds
            self.panHoldSeconds = panHoldSeconds
            self.cameraReturnSeconds = cameraReturnSeconds
            self.movementStartTimeoutSeconds = movementStartTimeoutSeconds
            self.movementSettleTimeoutSeconds = movementSettleTimeoutSeconds
            self.loopRestartSeconds = loopRestartSeconds
            self.maxLoops = maxLoops
        }
    }

    private let staging: WorldTutorialStaging
    private let performer: MinigameDemoPerforming
    private let timing: Timing

    init(
        staging: WorldTutorialStaging,
        performer: MinigameDemoPerforming,
        timing: Timing = Timing()
    ) {
        self.staging = staging
        self.performer = performer
        self.timing = timing
    }

    func run() async {
        await performer.pause(timing.settleSeconds)
        guard shouldContinue else { return }

        let anchor = staging.scenePoint(for: staging.spawnCoord)
        await staging.showTutorialChrome(cursorAt: anchor, fadeSeconds: timing.fadeSeconds)

        // Prologue: spoken once, held once. The loop below never repeats these.
        staging.speakIntro()
        await performer.pause(timing.leadInSeconds)

        if staging.demoTarget != nil {
            var cycle = 0
            while shouldContinue, cycle < timing.maxLoops {
                await runCycle()
                cycle += 1
                guard shouldContinue else { break }
                await performer.pause(timing.loopRestartSeconds)
            }
        }

        await staging.hideTutorialChrome(fadeSeconds: timing.fadeSeconds)
    }

    private var shouldContinue: Bool {
        !Task.isCancelled && !staging.isInterrupted
    }

    private func runCycle() async {
        guard shouldContinue, let demoTarget = staging.demoTarget else { return }

        let demoPoint = staging.scenePoint(for: demoTarget)
        await performer.perform(
            MinigameDemoMove(gesture: .tap(demoPoint), isCorrect: true),
            gestureSeconds: timing.dragSeconds
        )
        await waitForWalk()
        guard shouldContinue else { return }

        await performer.pause(timing.beatSeconds)
        guard shouldContinue else { return }

        staging.beginCameraOwnership()
        let dragFrom = staging.scenePoint(atViewFraction: CGPoint(x: 0.3, y: 0.3))
        let dragTo = staging.scenePoint(atViewFraction: CGPoint(x: 0.6, y: 0.6))
        await performer.perform(
            MinigameDemoMove(gesture: .drag(from: dragFrom, to: dragTo), isCorrect: true),
            gestureSeconds: timing.dragSeconds
        )
        guard shouldContinue else {
            staging.endCameraOwnership()
            return
        }

        await performer.pause(timing.panHoldSeconds)
        guard shouldContinue else {
            staging.endCameraOwnership()
            return
        }

        await staging.glideCameraToPlayer(duration: timing.cameraReturnSeconds)
        staging.endCameraOwnership()
        guard shouldContinue else { return }

        await performer.pause(timing.beatSeconds)
        guard shouldContinue else { return }

        let spawnPoint = staging.scenePoint(for: staging.spawnCoord)
        await performer.perform(
            MinigameDemoMove(gesture: .tap(spawnPoint), isCorrect: true),
            gestureSeconds: timing.dragSeconds
        )
        await waitForWalk()
    }

    /// Polls at 50ms until `condition` holds or `timeout` elapses. Returns false on
    /// timeout, cancellation, or interruption. Mirrors MinigameDemoRunner.waitUntilReady.
    private func wait(upTo timeout: TimeInterval, until condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !shouldContinue { return false }
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }

    /// Waits for the queued tap to become motion, then for that motion to finish.
    /// A start timeout is not fatal: the walk may already have completed.
    private func waitForWalk() async {
        _ = await wait(upTo: timing.movementStartTimeoutSeconds) {
            staging.isPlayerMoving
        }
        guard shouldContinue else { return }
        _ = await wait(upTo: timing.movementSettleTimeoutSeconds) {
            !staging.isPlayerMoving
        }
    }
}
