import Foundation

/// Abstraction over the virtual finger so unit tests can record moves without
/// driving a real `SKScene` touch stream.
@MainActor
protocol MinigameDemoPerforming: AnyObject {
    func pause(_ seconds: TimeInterval) async
    func perform(_ move: MinigameDemoMove, gestureSeconds: TimeInterval) async
}

extension MinigameDemoPointer: MinigameDemoPerforming {
    func perform(_ move: MinigameDemoMove, gestureSeconds: TimeInterval) async {
        switch move.gesture {
        case let .tap(point):
            await tap(at: point)
        case let .drag(from, to):
            await drag(from: from, to: to, duration: gestureSeconds)
        case let .swipe(points):
            await swipe(points, duration: 0.3)
        }
    }
}

@MainActor
final class MinigameDemoRunner {
    /// Value type kept `nonisolated` so it can be used as a default argument.
    nonisolated struct Timing: Sendable {
        var gestureSeconds: TimeInterval = 0.9
        /// The deliberate beat between the wrong move and the correct one.
        var beatSeconds: TimeInterval = 1.2
        var settleSeconds: TimeInterval = 0.4
        var readyTimeoutSeconds: TimeInterval = 12
        /// Upper bound on correct moves. Puzzle rounds are short enough to finish
        /// naturally; combat needs the cap (see "Combat length").
        var maxCorrectMoves: Int = 6
        /// Shown after "x" in the tally when the real award differs from the
        /// number of coins demonstrated.
        var displayedTotal: Int?

        nonisolated init(
            gestureSeconds: TimeInterval = 0.9,
            beatSeconds: TimeInterval = 1.2,
            settleSeconds: TimeInterval = 0.4,
            readyTimeoutSeconds: TimeInterval = 12,
            maxCorrectMoves: Int = 6,
            displayedTotal: Int? = nil
        ) {
            self.gestureSeconds = gestureSeconds
            self.beatSeconds = beatSeconds
            self.settleSeconds = settleSeconds
            self.readyTimeoutSeconds = readyTimeoutSeconds
            self.maxCorrectMoves = maxCorrectMoves
            self.displayedTotal = displayedTotal
        }
    }

    private let stage: MinigameDemoStage
    private let performer: MinigameDemoPerforming
    private let coins: MinigameDemoCoinLayer
    private let timing: Timing

    init(
        stage: MinigameDemoStage,
        pointer: MinigameDemoPointer,
        coins: MinigameDemoCoinLayer,
        timing: Timing = Timing()
    ) {
        self.stage = stage
        self.performer = pointer
        self.coins = coins
        self.timing = timing
    }

    /// Test seam: inject a fake performer that records moves without SpriteKit.
    init(
        stage: MinigameDemoStage,
        performer: MinigameDemoPerforming,
        coins: MinigameDemoCoinLayer,
        timing: Timing = Timing()
    ) {
        self.stage = stage
        self.performer = performer
        self.coins = coins
        self.timing = timing
    }

    func run() async {
        guard await waitUntilReady() else { return }

        // 1. The wrong move.
        if let wrong = stage.demoMoves.first(where: { !$0.isCorrect }) {
            await performer.perform(wrong, gestureSeconds: timing.gestureSeconds)
            guard await waitUntilReady() else { return }
            // 2. The pause.
            await performer.pause(timing.beatSeconds)
        }

        // 3. The correct move, then the rest of the round — one coin each.
        var awarded = 0
        while awarded < timing.maxCorrectMoves, !stage.demoIsFinished {
            guard await waitUntilReady() else { break }
            guard let correct = stage.demoMoves.first(where: { $0.isCorrect }) else { break }
            let moveAnchor = correct.coinAnchor
            await performer.perform(correct, gestureSeconds: timing.gestureSeconds)
            await performer.pause(timing.settleSeconds)
            if let anchor = moveAnchor ?? stage.demoCoinAnchor {
                coins.dropCoin(at: anchor)
                awarded += 1
            }
        }

        await coins.tally(total: timing.displayedTotal)
    }

    /// Polls rather than sleeping a fixed amount, so retiming any feedback
    /// animation cannot desync the demo.
    private func waitUntilReady() async -> Bool {
        let deadline = Date().addingTimeInterval(timing.readyTimeoutSeconds)
        while Date() < deadline {
            if Task.isCancelled { return false }
            if stage.demoIsFinished { return false }
            if stage.demoAcceptsInput, stage.demoMoves.contains(where: { $0.isCorrect }) {
                return true
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }
}
