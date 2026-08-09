import Foundation

/// Loops the gate tutorial: replay taps, a listen to every capacitor, a wrong drag,
/// the right drag, then a coin to the corner. Runs until its task is cancelled.
@MainActor
final class GateSoundOutWordDemoScript: MinigameDemoScript {
    /// Value type kept `nonisolated` so it can be used as a default argument.
    nonisolated struct Timing: Sendable {
        var gestureSeconds: TimeInterval
        /// Beat between the phases of a pass.
        var beatSeconds: TimeInterval
        /// Beat after a drop, before polling for readiness again.
        var settleSeconds: TimeInterval
        /// How long the finished circuit stays visible before a solved-word restart.
        var circuitHoldSeconds: TimeInterval
        var readyTimeoutSeconds: TimeInterval
        var pollSeconds: TimeInterval

        nonisolated init(
            gestureSeconds: TimeInterval = 0.9,
            beatSeconds: TimeInterval = 0.6,
            settleSeconds: TimeInterval = 0.4,
            circuitHoldSeconds: TimeInterval = 0.45,
            readyTimeoutSeconds: TimeInterval = 12,
            pollSeconds: TimeInterval = 0.05
        ) {
            self.gestureSeconds = gestureSeconds
            self.beatSeconds = beatSeconds
            self.settleSeconds = settleSeconds
            self.circuitHoldSeconds = circuitHoldSeconds
            self.readyTimeoutSeconds = readyTimeoutSeconds
            self.pollSeconds = pollSeconds
        }
    }

    private weak var stage: (any GateSoundOutWordDemoStaging)?
    private let timing: Timing

    init(stage: any GateSoundOutWordDemoStaging, timing: Timing = Timing()) {
        self.stage = stage
        self.timing = timing
    }

    func run(performer: MinigameDemoPerforming, coins: MinigameDemoCoinLayer) async {
        await run(performer: performer) { point in
            await coins.flyCoinToCorner(from: point)
        }
    }

    /// Test seam: the coin flight is injected so tests need no SpriteKit coin layer.
    func run(
        performer: MinigameDemoPerforming,
        flyCoin: (CGPoint) async -> Void
    ) async {
        while !Task.isCancelled {
            guard let stage else { return }
            guard await waitUntilReady() else {
                // Timed out, or the round ended while we waited: reset and try again
                // rather than leaving the tutorial screen frozen.
                guard !Task.isCancelled else { return }
                stage.demoRestart()
                // A restart that leaves the stage finished (test stop, or a dead scene)
                // must not spin forever.
                if stage.demoIsOver { return }
                continue
            }

            await demonstrateReplayTaps(performer: performer, stage: stage)
            await demonstrateChoiceTaps(performer: performer, stage: stage)

            if let wrong = stage.demoWrongMove {
                await performer.perform(wrong, gestureSeconds: timing.gestureSeconds)
                await performer.pause(timing.settleSeconds)
                guard await waitUntilReady() else { continue }
            }

            // Re-read after the reshuffle: every capacitor has moved.
            guard let correct = stage.demoCorrectMove else { continue }
            let anchor = correct.coinAnchor
            await performer.perform(correct, gestureSeconds: timing.gestureSeconds)
            await performer.pause(timing.settleSeconds)

            if let anchor { await flyCoin(anchor) }
            if stage.demoIsWordSolved || stage.demoIsOver {
                // Let the full endpoint → letters → endpoint arc read before teardown.
                await performer.pause(timing.circuitHoldSeconds)
                stage.demoRestart()
            }
        }
    }

    private func demonstrateReplayTaps(
        performer: MinigameDemoPerforming,
        stage: any GateSoundOutWordDemoStaging
    ) async {
        if let point = stage.demoPictureTap {
            await tap(point, performer: performer)
            await performer.pause(stage.demoWordCueSeconds)
        }
        if let point = stage.demoWordPlateTap {
            await tap(point, performer: performer)
            await performer.pause(stage.demoLetterNameCueSeconds)
        }
        await performer.pause(timing.beatSeconds)
    }

    private func demonstrateChoiceTaps(
        performer: MinigameDemoPerforming,
        stage: any GateSoundOutWordDemoStaging
    ) async {
        for cue in stage.demoChoiceTaps {
            if Task.isCancelled { return }
            await tap(cue.point, performer: performer)
            await performer.pause(cue.seconds)
        }
        await performer.pause(timing.beatSeconds)
    }

    private func tap(_ point: CGPoint, performer: MinigameDemoPerforming) async {
        await performer.perform(
            MinigameDemoMove(gesture: .tap(point), isCorrect: false),
            gestureSeconds: timing.gestureSeconds
        )
    }

    /// Polls rather than sleeping a fixed amount, so retiming any feedback animation
    /// cannot desync the demo (same shape as `MinigameDemoRunner.waitUntilReady`).
    private func waitUntilReady() async -> Bool {
        let deadline = Date().addingTimeInterval(timing.readyTimeoutSeconds)
        while Date() < deadline {
            if Task.isCancelled { return false }
            guard let stage else { return false }
            if stage.demoIsOver { return false }
            if stage.demoIsReady, stage.demoCorrectMove != nil { return true }
            try? await Task.sleep(nanoseconds: UInt64(timing.pollSeconds * 1_000_000_000))
        }
        return false
    }
}
