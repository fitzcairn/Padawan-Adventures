import SpriteKit
import UIKit

protocol PitBridgeSceneDelegate: AnyObject {
    func pitBridgeSceneDidUpdateWord(_ word: String)
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
    let speaker = PhonicsSpeaker()
    var placementRNG = SystemRandomNumberGenerator()

    var playerNode: SKNode?
    var playerSprite: AnimatedSpriteNode?
    var playerFacingLeft = false
    var trayNodes: [UUID: SKNode] = [:]
    var placedTileNodes: [SKNode] = []
    var slotBoxNode: SKShapeNode?
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
    static let playerZ: CGFloat = 1_000
    static let padsZ: CGFloat = 1
    static let placedTilesZ: CGFloat = 5
    static let slotBoxZ: CGFloat = 8
    static let trayTilesZ: CGFloat = 10
    static let draggedZ: CGFloat = 60
    static let promptWatchdogSeconds: TimeInterval = 10
    static let promptWatchdogKey = "pitBridgePromptWatchdog"
    static let winSoundActionKey = "pitBridgeWinSound"
    static let springBackDuration: TimeInterval = 0.18

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
        speaker.cancel()
        removeAction(forKey: Self.promptWatchdogKey)
    }

    override func rebuildLayout() {
        repositionForNewSize()
    }
}
