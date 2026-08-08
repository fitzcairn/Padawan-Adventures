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
}
