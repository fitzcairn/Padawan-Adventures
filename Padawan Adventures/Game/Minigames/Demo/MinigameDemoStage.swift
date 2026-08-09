import CoreGraphics

/// One candidate gesture the demo could perform right now.
struct MinigameDemoMove {
    enum Gesture {
        case tap(CGPoint)
        case drag(from: CGPoint, to: CGPoint)
        case swipe([CGPoint])
    }

    let gesture: Gesture
    let isCorrect: Bool
    /// Preferred coin drop point for this move. When nil, the runner falls back to
    /// `MinigameDemoStage.demoCoinAnchor` after the move settles.
    let coinAnchor: CGPoint?

    init(gesture: Gesture, isCorrect: Bool, coinAnchor: CGPoint? = nil) {
        self.gesture = gesture
        self.isCorrect = isCorrect
        self.coinAnchor = coinAnchor
    }
}

/// Per-scene adapter telling the demo runner where to point.
///
/// Every property must be computed from live nodes and engine state at call time —
/// never cached — so the demo stays correct after shuffles and relayouts.
@MainActor
protocol MinigameDemoStage: AnyObject {
    /// True when the scene will act on a new gesture right now.
    var demoAcceptsInput: Bool { get }
    /// Candidate moves for the current step. Must contain exactly one correct move
    /// when the scene is mid-round.
    var demoMoves: [MinigameDemoMove] { get }
    /// Where the coin earned by the move just completed should land.
    var demoCoinAnchor: CGPoint? { get }
    /// True once the round is over; the runner stops.
    var demoIsFinished: Bool { get }
    /// True when this stage demonstrates a non-scoring affordance before the main
    /// wrong-then-right sequence. Stages without one skip the prelude polling entirely.
    var demoDemonstratesPrelude: Bool { get }
    /// Prelude gesture(s) when they are performable right now; empty while they are not
    /// (the combat orb, for instance, is only tappable early in its flight).
    var demoPreludeMoves: [MinigameDemoMove] { get }
    /// Non-nil when this stage drives its own choreography instead of the generic
    /// wrong-then-right sequence.
    var demoScript: MinigameDemoScript? { get }
    /// When non-nil, `waitForConsequence` waits until this becomes `false` (payoff
    /// landed — e.g. the reflected letter hitting the enemy). When nil, the runner
    /// falls back to waiting until `demoAcceptsInput` again.
    var demoConsequenceInFlight: Bool? { get }
    /// Replays begin-of-minigame SFX after the tutorial lead-in unsuppresses gameplay
    /// audio. Default is a no-op for stages with no opening cues.
    func demoResumeGameplayAudio()
}

extension MinigameDemoStage {
    var demoDemonstratesPrelude: Bool { false }
    var demoPreludeMoves: [MinigameDemoMove] { [] }
    var demoScript: MinigameDemoScript? { nil }
    var demoConsequenceInFlight: Bool? { nil }
    func demoResumeGameplayAudio() {}
}
