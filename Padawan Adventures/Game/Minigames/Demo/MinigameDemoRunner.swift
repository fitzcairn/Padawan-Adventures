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

/// Bespoke choreography for one minigame, replacing the generic wrong-then-right
/// sequence. Runs until it returns or its task is cancelled.
@MainActor
protocol MinigameDemoScript: AnyObject {
    func run(performer: MinigameDemoPerforming, coins: MinigameDemoCoinLayer) async
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
        /// How long to wait for a non-scoring prelude gesture (e.g. tap the orb).
        var preludeTimeoutSeconds: TimeInterval = 10
        /// Upper bound on correct moves. Puzzle rounds are short enough to finish
        /// naturally; combat needs the cap (see "Combat length").
        var maxCorrectMoves: Int = 6
        /// How long the won coins sit before arcing into the corner.
        var coinHoldSeconds: TimeInterval = 1.0
        var coinFlightSeconds: TimeInterval = 0.75
        /// Upper bound on waiting for a move's animation to land.
        var consequenceTimeoutSeconds: TimeInterval = 8

        nonisolated init(
            gestureSeconds: TimeInterval = 0.9,
            beatSeconds: TimeInterval = 1.2,
            settleSeconds: TimeInterval = 0.4,
            readyTimeoutSeconds: TimeInterval = 12,
            preludeTimeoutSeconds: TimeInterval = 10,
            maxCorrectMoves: Int = 6,
            coinHoldSeconds: TimeInterval = 1.0,
            coinFlightSeconds: TimeInterval = 0.75,
            consequenceTimeoutSeconds: TimeInterval = 8
        ) {
            self.gestureSeconds = gestureSeconds
            self.beatSeconds = beatSeconds
            self.settleSeconds = settleSeconds
            self.readyTimeoutSeconds = readyTimeoutSeconds
            self.preludeTimeoutSeconds = preludeTimeoutSeconds
            self.maxCorrectMoves = maxCorrectMoves
            self.coinHoldSeconds = coinHoldSeconds
            self.coinFlightSeconds = coinFlightSeconds
            self.consequenceTimeoutSeconds = consequenceTimeoutSeconds
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

    @discardableResult
    func run() async -> Int {
        if let script = stage.demoScript {
            // Scripted demos own their own looping / coin visuals. Returning 0 keeps
            // `MinigameDemoController.runLoop` from starting a second cycle after cancel.
            await script.run(performer: performer, coins: coins)
            return 0
        }

        guard await waitUntilReady() else { return 0 }

        // 0. The non-scoring affordance (combat: tap the orb to hear its word again).
        if stage.demoDemonstratesPrelude, await waitForPrelude() {
            for move in stage.demoPreludeMoves {
                await performer.perform(move, gestureSeconds: timing.gestureSeconds)
                await performer.pause(timing.beatSeconds)
            }
            guard await waitUntilReady() else { return 0 }
        }

        // 1. The wrong move.
        if let wrong = stage.demoMoves.first(where: { !$0.isCorrect }) {
            await performer.perform(wrong, gestureSeconds: timing.gestureSeconds)
            guard await waitUntilReady() else { return 0 }
            // 2. The pause.
            await performer.pause(timing.beatSeconds)
        }

        // 3. The correct move, then the rest of the round — one coin each, flown to
        // the corner as soon as the move's consequence lands (e.g. monster HP hits 0).
        var awarded = 0
        while awarded < timing.maxCorrectMoves, !stage.demoIsFinished {
            guard await waitUntilReady() else { break }
            guard let correct = stage.demoMoves.first(where: { $0.isCorrect }) else { break }
            let moveAnchor = correct.coinAnchor
            await performer.perform(correct, gestureSeconds: timing.gestureSeconds)
            await performer.pause(timing.settleSeconds)
            // The slash / tap is not the payoff: the reflected letter (or deflected orb)
            // still has to reach the monster before the coin drops.
            await waitForConsequence()
            if let anchor = moveAnchor ?? stage.demoCoinAnchor {
                await coins.flyCoinToCorner(
                    from: anchor,
                    holdSeconds: timing.coinHoldSeconds,
                    flightSeconds: timing.coinFlightSeconds
                )
                awarded += 1
            }
        }

        return awarded
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

    /// Polls for a performable prelude. Separate from `waitUntilReady` because the
    /// combat orb is only tappable while it is still clear of the ring cluster, so the
    /// runner may have to wait for the next throw — and gives up rather than stalling
    /// the whole tutorial screen.
    private func waitForPrelude() async -> Bool {
        let deadline = Date().addingTimeInterval(timing.preludeTimeoutSeconds)
        while Date() < deadline {
            if Task.isCancelled || stage.demoIsFinished { return false }
            if stage.demoAcceptsInput, !stage.demoPreludeMoves.isEmpty { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }

    /// Blocks until the move just performed has actually landed. The gesture is not the
    /// payoff: a reflected letter / deflected orb still has to fly back and drain the
    /// monster's HP bar, and the coin has to appear with that, not with the swipe.
    private func waitForConsequence() async {
        let deadline = Date().addingTimeInterval(timing.consequenceTimeoutSeconds)
        while Date() < deadline {
            if Task.isCancelled { return }
            if stage.demoIsFinished { return }
            if let inFlight = stage.demoConsequenceInFlight {
                if !inFlight { return }
            } else if stage.demoAcceptsInput {
                return
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
