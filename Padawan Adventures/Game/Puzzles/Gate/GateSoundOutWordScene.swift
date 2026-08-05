import SpriteKit
import UIKit

protocol GateSoundOutWordSceneDelegate: AnyObject {
    func gateSoundOutWordSceneDidWin(starsAwarded: Int)
}

/// SpriteKit gate sound-out-word puzzle: the word and its picture sit at the top, and the
/// player drags one blank capacitor per grapheme into the play area, left to right.
final class GateSoundOutWordScene: MinigameScene {
    static let promptFlashPeriod: TimeInterval = 0.16
    static let wrongFlashPeriod: TimeInterval = 0.12
    static let solvedFlashPeriod: TimeInterval = 0.16
    static let returnHomeDuration: TimeInterval = 0.3
    /// Duration for the post-miss capacitor reshuffle slide.
    static let shuffleDuration: TimeInterval = 0.35
    static let setFadeDuration: TimeInterval = 0.35
    static let letterRevealDuration: TimeInterval = 0.25
    /// Brief beat after the final connector appears, before the word read-back.
    static let winConnectorHoldDuration: TimeInterval = 0.45
    /// How often connector bolts re-jag for the electricity flicker.
    static let electricityRefreshInterval: TimeInterval = 0.045
    static let winSequenceActionKey = "gateSoundOutWordWin"
    static let promptActionKey = "gateSoundOutWordPrompt"
    static let feedbackActionKey = "gateSoundOutWordFeedback"

    weak var soundOutWordDelegate: GateSoundOutWordSceneDelegate?

    let puzzleConfig: GateSoundOutWordConfig

    var engine: GateSoundOutWordEngine

    // MARK: Nodes

    var pictureNode: SKSpriteNode?
    /// One outlined-letter stack per grapheme of the word, left to right.
    var promptLetterNodes: [SKNode] = []
    var leftEndpointNode: SKNode?
    var rightEndpointNode: SKNode?
    /// Capacitors already placed in the play area, in spelling order.
    var placedNodes: [SKNode] = []
    /// Placed positions as fractions of the play area, so resizes keep the layout.
    var placedFractions: [CGPoint] = []
    /// Blank capacitors currently on offer, keyed by engine choice id.
    var choiceNodes: [UUID: SKNode] = [:]
    var choiceHome: [UUID: CGPoint] = [:]
    var connectorSegments: [ElectricConnector] = []
    /// Cached white `play` / `play.fill` textures for the current choice-icon side.
    var playIconTextures: (side: CGFloat, idle: SKTexture, filled: SKTexture)?

    // MARK: State

    var laidOutDiameter: CGFloat = 0
    var electricityRefreshAccumulator: TimeInterval = 0
    var electricityRNG = SystemRandomNumberGenerator()
    var lastUpdateTime: TimeInterval?
    var activeLoopTrackID: String?
    /// Blocks new drags while feedback or a prompt is playing. Taps stay live.
    var inputLocked = false
    var isCompletingWin = false
    var dragChoiceID: UUID?
    var dragOffset: CGPoint = .zero
    var dragStart: CGPoint = .zero
    var dragMoved = false

    let tapMoveThreshold: CGFloat = 10

    let promptPendingColor = UIColor.white
    let promptActiveColor = UIColor.systemOrange
    let promptSolvedFlashColor = UIColor(red: 0.30, green: 0.90, blue: 0.40, alpha: 1)
    let capacitorWrongFlash = UIColor.systemRed
    /// Bright blue tint for the completed start → graphemes → stop chain.
    let capacitorSolvedTint = UIColor(red: 0.20, green: 0.55, blue: 1.0, alpha: 1)
    let capacitorTintBlend: CGFloat = 0.55
    /// Subtle per-capacitor wash so blank faces in a set stay distinguishable.
    let choiceTints: [UIColor] = [
        UIColor(red: 0.60, green: 0.72, blue: 0.96, alpha: 1),
        UIColor(red: 0.96, green: 0.80, blue: 0.60, alpha: 1),
        UIColor(red: 0.66, green: 0.93, blue: 0.76, alpha: 1),
        UIColor(red: 0.94, green: 0.72, blue: 0.87, alpha: 1),
        UIColor(red: 0.87, green: 0.91, blue: 0.60, alpha: 1),
        UIColor(red: 0.74, green: 0.83, blue: 0.93, alpha: 1),
    ]
    let choiceTintBlend: CGFloat = 0.55
    /// Fallback circle colors when the capacitor texture fails to load.
    let circleFill = UIColor(white: 0.22, alpha: 1)
    let connectorColor = UIColor(red: 0.55, green: 0.82, blue: 1.0, alpha: 1)
    let connectorCoreColor = UIColor(red: 0.85, green: 0.95, blue: 1.0, alpha: 1)

    init(
        size: CGSize,
        puzzleConfig: GateSoundOutWordConfig
    ) {
        self.puzzleConfig = puzzleConfig
        self.engine = GateSoundOutWordEngine(config: .init(from: puzzleConfig))
        super.init(size: size)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func buildContent() {
        engine.begin()
        GameLogger.step(.world, "gateSoundOutWord.buildPuzzle") { buildPuzzle() }
        beginRound()
    }

    override func willMove(from view: SKView) {
        GameLogger.mark(.world, "gateSoundOutWord.willMove teardown")
        stopGateLoop()
    }

    override func rebuildLayout() {
        buildPuzzle()
        restoreProgress()
    }

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdateTime.map { min(max(currentTime - $0, 0), 0.05) } ?? (1.0 / 60.0)
        lastUpdateTime = currentTime
        refreshElectricityConnectors(dt: dt)
    }

    // MARK: - Touch / drag

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !didEnd, !isCompletingWin, let touch = touches.first else { return }
        let point = touch.location(in: self)

        if let choiceID = choice(at: point) {
            // Letter sound plays on touch-down, whether this becomes a tap or a drag.
            playChoiceSound(choiceID: choiceID)
            guard !inputLocked, let node = choiceNodes[choiceID] else { return }
            dragChoiceID = choiceID
            dragStart = point
            dragMoved = false
            dragOffset = CGPoint(x: node.position.x - point.x, y: node.position.y - point.y)
            node.zPosition = 50
            return
        }

        if isPromptWordTap(point) {
            // Word taps always name the active (orange) letter, not whichever glyph was hit.
            playCurrentPromptLetterName()
            return
        }

        if isPictureTap(point) {
            playWordSound()
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !didEnd, !isCompletingWin, let touch = touches.first,
              let dragChoiceID, let node = choiceNodes[dragChoiceID] else { return }
        let point = touch.location(in: self)
        if hypot(point.x - dragStart.x, point.y - dragStart.y) > tapMoveThreshold {
            dragMoved = true
        }
        let radius = laidOutDiameter * 0.5
        node.position = CGPoint(
            x: min(max(point.x + dragOffset.x, radius), size.width - radius),
            y: min(max(point.y + dragOffset.y, radius), maxPlayableCenterY(for: radius))
        )
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        endDrag()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let dragChoiceID else { return }
        self.dragChoiceID = nil
        dragMoved = false
        choiceNodes[dragChoiceID]?.zPosition = 20
        animateChoiceHome(dragChoiceID)
    }

    func endDrag() {
        guard let choiceID = dragChoiceID, let node = choiceNodes[choiceID] else { return }
        dragChoiceID = nil
        let moved = dragMoved
        dragMoved = false
        node.zPosition = 20

        // A tap in place only plays the letter sound (already fired on touch-down).
        guard moved else {
            animateChoiceHome(choiceID)
            return
        }

        if isValidDrop(node.position) {
            resolveDrop(choiceID: choiceID, isPlacementValid: true)
            return
        }

        // Near miss: dragged closer to the play area than home — ease into the nearest
        // legal spot, then accept or reject from there.
        if let home = choiceHome[choiceID],
           let target = nearestValidDropPoint(to: node.position),
           distanceToPlayArea(node.position) < distanceToPlayArea(home) {
            runAssistedPlacement(choiceID: choiceID, to: target)
            return
        }

        resolveDrop(choiceID: choiceID, isPlacementValid: false)
    }

    func resolveDrop(choiceID: UUID, isPlacementValid: Bool) {
        switch engine.drop(choiceID: choiceID, isPlacementValid: isPlacementValid) {
        case .accepted:
            runAcceptedPlacement(choiceID: choiceID)
        case .rejected:
            runRejectedPlacement(choiceID: choiceID)
        }
    }
}
