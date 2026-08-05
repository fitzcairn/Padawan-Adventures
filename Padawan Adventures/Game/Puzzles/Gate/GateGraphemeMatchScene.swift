import SpriteKit
import UIKit

protocol GateGraphemeMatchSceneDelegate: AnyObject {
    func gateGraphemeMatchSceneDidWin(starsAwarded: Int)
}

/// SpriteKit gate letter-match puzzle: switch letter buttons.
final class GateGraphemeMatchScene: MinigameScene {
    weak var graphemeMatchDelegate: GateGraphemeMatchSceneDelegate?

    let puzzleConfig: GateGraphemeMatchConfig

    var engine: GateGraphemeMatchMinigameEngine
    var letterNodes: [UUID: SKNode] = [:]
    var switchNodes: [UUID: SKSpriteNode] = [:]
    var switchTextures: GateGraphemeMatchSwitchSprites.Textures?
    /// Side length used by the last `layoutLetterRow` (for hit-testing).
    var laidOutTileSide: CGFloat = 0
    var inputLocked = false

    let squareFill = UIColor(red: 0.45, green: 0.28, blue: 0.12, alpha: 1)
    let squareMatchedFill = UIColor(red: 0.20, green: 0.65, blue: 0.28, alpha: 1)
    let squareWrongFill = UIColor.systemRed

    init(
        size: CGSize,
        puzzleConfig: GateGraphemeMatchConfig
    ) {
        self.puzzleConfig = puzzleConfig
        self.engine = GateGraphemeMatchMinigameEngine(config: .init(from: puzzleConfig))
        super.init(size: size)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func buildContent() {
        engine.begin()
        GameLogger.step(.world, "gateLetterMatch.buildPuzzle") { buildPuzzle() }
        playTargetPronunciation()
    }
    /// Preferred gap as a fraction of tile side; compress toward `minGapRatio` before shrinking tiles.
    let preferredGapRatio: CGFloat = 0.18
    let minGapRatio: CGFloat = 0.04
    /// Horizontal inset inside the background so switches don't kiss the art edges.
    let backgroundEdgeInsetRatio: CGFloat = 0.05

    struct LetterRowLayout {
        let side: CGFloat
        let gap: CGFloat
        let firstCenterX: CGFloat
        let centerY: CGFloat
    }
    override func rebuildLayout() {
        let matched = engine.matchedIDs
        buildPuzzle()
        for id in matched {
            applyMatchedAppearance(id: id)
        }
    }
}
