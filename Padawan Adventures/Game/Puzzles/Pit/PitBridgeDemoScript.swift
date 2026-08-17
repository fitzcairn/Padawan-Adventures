import Foundation

/// Loops the pit-bridge tutorial: correct first tile, then wrong→right on the
/// second tile with a coin each time, then the "tap to continue" cue and a
/// restart. Runs until cancelled.
@MainActor
final class PitBridgeDemoScript: MinigameDemoScript {
    /// Value type kept `nonisolated` so it can be used as a default argument.
    nonisolated struct Timing: Sendable {
        var gestureSeconds: TimeInterval
        /// Beat between the wrong move and the correct one on tile 2.
        var beatSeconds: TimeInterval
        /// Beat after a drop, before polling for readiness again.
        var settleSeconds: TimeInterval
        /// How long the second placed tile stays visible before a restart.
        var holdSeconds: TimeInterval
        var readyTimeoutSeconds: TimeInterval
        var pollSeconds: TimeInterval

        nonisolated init(
            gestureSeconds: TimeInterval = 0.9,
            beatSeconds: TimeInterval = 1.2,
            settleSeconds: TimeInterval = 0.4,
            holdSeconds: TimeInterval = 0.45,
            readyTimeoutSeconds: TimeInterval = 12,
            pollSeconds: TimeInterval = 0.05
        ) {
            self.gestureSeconds = gestureSeconds
            self.beatSeconds = beatSeconds
            self.settleSeconds = settleSeconds
            self.holdSeconds = holdSeconds
            self.readyTimeoutSeconds = readyTimeoutSeconds
            self.pollSeconds = pollSeconds
        }
    }

    private weak var stage: (any PitBridgeDemoStaging)?
    private let timing: Timing

    init(stage: any PitBridgeDemoStaging, timing: Timing = Timing()) {
        self.stage = stage
        self.timing = timing
    }

    func run(performer: MinigameDemoPerforming, coins: MinigameDemoCoinLayer) async {
        await run(performer: performer) { point in
            await coins.flyCoinToCorner(from: point)
        } onLoopBoundary: {
            await MinigameTutorialVoiceOver.playContinueCue()
        }
    }

    /// Test seam: the coin flight and the end-of-pass cue are injected so tests need
    /// no SpriteKit coin layer and no audio.
    func run(
        performer: MinigameDemoPerforming,
        flyCoin: (CGPoint) async -> Void,
        onLoopBoundary: () async -> Void = {}
    ) async {
        while !Task.isCancelled {
            guard let stage else { return }

            // 1. Correct first tile (establishes the bridge; no wrong attempt).
            guard await waitUntilReady() else {
                guard !Task.isCancelled else { return }
                stage.demoRestart()
                if stage.demoIsOver { return }
                continue
            }
            guard let first = stage.demoCorrectMove else { continue }
            let firstAnchor = first.coinAnchor
            await performer.perform(first, gestureSeconds: timing.gestureSeconds)
            await performer.pause(timing.settleSeconds)
            if let firstAnchor { await flyCoin(firstAnchor) }

            // 2. Wrong then right on the second tile — the looping teaching beat.
            guard await waitUntilReady() else { continue }
            if let wrong = stage.demoWrongMove {
                await performer.perform(wrong, gestureSeconds: timing.gestureSeconds)
                await performer.pause(timing.settleSeconds)
                guard await waitUntilReady() else { continue }
                await performer.pause(timing.beatSeconds)
            }

            // Re-read after the reshuffle: every tray tile has moved.
            guard let second = stage.demoCorrectMove else { continue }
            let secondAnchor = second.coinAnchor
            await performer.perform(second, gestureSeconds: timing.gestureSeconds)
            await performer.pause(timing.settleSeconds)
            if let secondAnchor { await flyCoin(secondAnchor) }

            await performer.pause(timing.holdSeconds)
            guard !Task.isCancelled else { return }
            await onLoopBoundary()
            guard !Task.isCancelled else { return }
            stage.demoRestart()
            if stage.demoIsOver { return }
        }
    }

    /// Polls rather than sleeping a fixed amount, so retiming any feedback
    /// animation cannot desync the demo (same shape as `MinigameDemoRunner.waitUntilReady`).
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
