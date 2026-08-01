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
    var plateNodes: [UUID: SKShapeNode] = [:]
    var socketNodes: [UUID: SKShapeNode] = [:]
    var tokenNodes: [UUID: SKNode] = [:]
    var tokenCircles: [UUID: SKShapeNode] = [:]
    var tokenHome: [UUID: CGPoint] = [:]
    var laidOutDiameter: CGFloat = 0
    var laidOutRectSize: CGSize = .zero

    var inputLocked = false

    var dragTokenID: UUID?
    var dragStart: CGPoint = .zero
    var dragOffset: CGPoint = .zero
    var dragMoved = false

    let trayHeightRatio: CGFloat = 0.30
    let columnCount = 2
    let gridInsetXRatio: CGFloat = 0.04
    let gridInsetYRatio: CGFloat = 0.06
    let columnGapRatio: CGFloat = 0.06
    let rowGapRatio: CGFloat = 0.18
    let socketWidthShareMax: CGFloat = 0.45
    let tapMoveThreshold: CGFloat = 10

    let rectFill = UIColor(red: 0.06, green: 0.14, blue: 0.36, alpha: 1)
    let rectStroke = UIColor(white: 0.28, alpha: 1)
    let socketFill = UIColor(white: 0.55, alpha: 1)
    let socketStroke = UIColor.white
    let tokenFill = UIColor(white: 0.28, alpha: 1)
    let tokenStroke = UIColor(white: 0.80, alpha: 1)
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
        // The speaker is a shared singleton; without this a phrase (and its music
        // duck) keeps running after the gate overlay is dismissed.
        SpokenPhrasePlayer.shared.cancel()
    }
    override func rebuildLayout() {
        let plugged = engine.plugged
        buildPuzzle()
        for (slotID, letterID) in plugged {
            applySolvedAppearance(slotID: slotID)
            if let socket = socketNodes[slotID], let token = tokenNodes[letterID] {
                token.position = socket.position
                token.zPosition = 20
            }
        }
    }
}
extension SKAction {
    func withTimingMode(_ mode: SKActionTimingMode) -> SKAction {
        timingMode = mode
        return self
    }
}
