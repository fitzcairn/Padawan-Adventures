import SpriteKit
import UIKit

protocol GateWordPlugSceneDelegate: AnyObject {
    func gateWordPlugSceneDidWin(starsAwarded: Int)
}

/// SpriteKit gate word-plug puzzle: drag first-letter parts onto word sockets.
final class GateWordPlugScene: MinigameScene {
    weak var wordPlugDelegate: GateWordPlugSceneDelegate?

    let puzzleConfig: GateWordPlugConfig
    let playerFx: SoundEffectTable

    var engine: GateWordPlugMinigameEngine
    var plateNodes: [UUID: SKSpriteNode] = [:]
    var socketNodes: [UUID: SKSpriteNode] = [:]
    var socketSpriteRNG = SystemRandomNumberGenerator()
    var tokenNodes: [UUID: SKNode] = [:]
    var tokenPlugs: [UUID: SKSpriteNode] = [:]
    var tokenHome: [UUID: CGPoint] = [:]
    var laidOutDiameter: CGFloat = 0
    var laidOutRectSize: CGSize = .zero

    var inputLocked = false

    var dragTokenID: UUID?
    var dragStart: CGPoint = .zero
    var dragOffset: CGPoint = .zero
    var dragMoved = false
    /// Active cables keyed by letter token id (kept after a correct plug).
    var tokenCables: [UUID: DragCable] = [:]
    var cableLastUpdateTime: TimeInterval?
    var cableArcRefreshAccumulator: TimeInterval = 0
    var cableArcRNG = SystemRandomNumberGenerator()
    /// Quiet arc ambience while at least one plug is correctly connected.
    var activeLoopTrackID: String?
    static let arcLoopQuietScale: Float = 0.35
    static let arcLoopFallbackTrackID = "gate-spelling-loop-arc"

    let trayHeightRatio: CGFloat = 0.30
    /// Preferred column count; becomes 3 when 2 columns can't balance or the board is too wide.
    var boardColumnCount = 2
    let preferredColumnCount = 2
    let expandedColumnCount = 3
    /// Floor for vertical sizing so 1–2 word boards don't inflate to full play-area height.
    let minLayoutRows = 3
    /// Multiplier on the sparse-board size cap (1.0 = baseline from `minLayoutRows`).
    let sizeCapScale: CGFloat = 1.2
    let gridInsetXRatio: CGFloat = 0.04
    let gridInsetYRatio: CGFloat = 0.06
    let columnGapRatio: CGFloat = 0.06
    let rowGapRatio: CGFloat = 0.18
    let socketWidthShareMax: CGFloat = 0.45
    /// Drawn size of plugs/sockets relative to a filled-slot layout.
    let uiScale: CGFloat = 0.75
    let tapMoveThreshold: CGFloat = 10

    let solvedFill = UIColor(red: 0.20, green: 0.72, blue: 0.30, alpha: 1)
    let wrongFill = UIColor.systemRed

    init(
        size: CGSize,
        puzzleConfig: GateWordPlugConfig,
        playerFx: SoundEffectTable
    ) {
        self.puzzleConfig = puzzleConfig
        self.playerFx = playerFx
        self.engine = GateWordPlugMinigameEngine(config: .init(from: puzzleConfig))
        super.init(size: size)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func buildContent() {
        engine.begin()
        GameLogger.step(.world, "gateWordPlug.buildPuzzle") { buildPuzzle() }
    }

    override func willMove(from view: SKView) {
        GameLogger.mark(.world, "gateWordPlug.willMove teardown")
        stopArcLoop()
        // The speaker is a shared singleton; without this a phrase (and its music
        // duck) keeps running after the gate overlay is dismissed.
        SpokenPhrasePlayer.shared.cancel()
    }
    override func rebuildLayout() {
        tearDownAllCables()
        let plugged = engine.plugged
        buildPuzzle()
        for (slotID, letterID) in plugged {
            applySolvedAppearance(slotID: slotID)
            if let socket = socketNodes[slotID], let token = tokenNodes[letterID] {
                token.position = socket.position
                token.zPosition = 20
            }
        }
        restorePluggedCables()
        syncArcLoop()
    }

    override func update(_ currentTime: TimeInterval) {
        updateDragCables(currentTime: currentTime)
    }
}
extension SKAction {
    func withTimingMode(_ mode: SKActionTimingMode) -> SKAction {
        timingMode = mode
        return self
    }
}
