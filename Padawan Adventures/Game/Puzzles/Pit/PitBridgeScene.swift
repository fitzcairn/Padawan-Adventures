import SpriteKit
import UIKit

protocol PitBridgeSceneDelegate: AnyObject {
    func pitBridgeSceneDidWin(starsAwarded: Int)
}

/// SpriteKit pit-bridge puzzle: side pads, dashed slots, draggable lettered floor tiles.
final class PitBridgeScene: MinigameScene {
    weak var bridgeDelegate: PitBridgeSceneDelegate?

    let bridgeConfig: PitBridgeConfig
    let pitFx: SoundEffectTable
    let playerFx: SoundEffectTable
    let floorTileSetLibrary: FloorTileSetLibrary
    let isoConfig: IsometricConfig
    let spriteLibrary: SpriteLibrary
    let playerSpriteConfig: SpriteConfig?

    var engine: PitBridgeMinigameEngine
    var placementRNG = SystemRandomNumberGenerator()

    var playerNode: SKNode?
    var playerSprite: AnimatedSpriteNode?
    var playerFacingLeft = false
    var trayNodes: [UUID: SKNode] = [:]
    var placedTileNodes: [SKNode] = []
    var slotBoxNode: SKShapeNode?
    var wordPromptNode: SKNode?
    /// Answer-letter blank under the word illustration (`_` until a tile is dropped).
    var blankLetterNode: SKNode?
    var draggedNode: SKNode?
    var dragOffset: CGPoint = .zero
    var dragStartPosition: CGPoint = .zero

    var isJumping = false
    var didRevealTrayForRound = false
    var promptContinuationArmed = false

    let padFill = UIColor(red: 0.45, green: 0.28, blue: 0.12, alpha: 1)
    let platformCorrectTint = UIColor(red: 0.20, green: 0.65, blue: 0.28, alpha: 1)
    let platformWrongTint = UIColor.systemRed
    let playerFill = UIColor.systemRed

    static let jumpDuration: TimeInterval = 1.0
    static let playerLibraryID = "player"
    static let playerZ: CGFloat = SceneLayer.player
    static let padsZ: CGFloat = SceneLayer.pads
    static let placedTilesZ: CGFloat = SceneLayer.placedTiles
    static let slotBoxZ: CGFloat = SceneLayer.slotBox
    static let trayTilesZ: CGFloat = SceneLayer.trayTiles
    static let draggedZ: CGFloat = SceneLayer.dragged
    static let wordPromptZ: CGFloat = SceneLayer.overlay
    static let promptWatchdogSeconds: TimeInterval = 10
    static let promptWatchdogKey = "pitBridgePromptWatchdog"
    static let promptSoundKey = "pitBridgePromptSound"
    static let letterCueActionKey = "pitBridgeLetterCue"
    static let winSoundActionKey = "pitBridgeWinSound"
    static let springBackDuration: TimeInterval = 0.18
    /// Ease a near-miss drop into the dashed slot before resolving correct/incorrect.
    static let snapIntoSlotDuration: TimeInterval = 0.18
    static let snapIntoSlotActionKey = "snapIntoSlot"
    static let forceLiftSparkleCleanupKey = "forceLiftSparkleCleanup"
    static let wordPromptNodeName = "wordPrompt"
    static let blankLetterNodeName = "blankLetter"
    static let wordSpellingNodeName = "wordSpelling"

    init(
        size: CGSize,
        bridgeConfig: PitBridgeConfig,
        pitFx: SoundEffectTable,
        playerFx: SoundEffectTable,
        floorTileSetLibrary: FloorTileSetLibrary,
        isoConfig: IsometricConfig,
        spriteLibrary: SpriteLibrary,
        playerSpriteConfig: SpriteConfig?
    ) {
        self.bridgeConfig = bridgeConfig
        self.pitFx = pitFx
        self.playerFx = playerFx
        self.floorTileSetLibrary = floorTileSetLibrary
        self.isoConfig = isoConfig
        self.spriteLibrary = spriteLibrary
        self.playerSpriteConfig = playerSpriteConfig
        self.engine = PitBridgeMinigameEngine(config: .init(from: bridgeConfig))
        super.init(size: size)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func buildContent() {
        engine.begin()
        GameLogger.step(.world, "pitBridge.buildArena") { buildArena() }
        beginRound()
    }

    override func willMove(from view: SKView) {
        GameLogger.mark(.world, "pitBridge.willMove teardown")
        removeAction(forKey: Self.promptWatchdogKey)
        removeAction(forKey: Self.promptSoundKey)
        removeAction(forKey: Self.letterCueActionKey)
    }

    override func rebuildLayout() {
        repositionForNewSize()
    }
}
