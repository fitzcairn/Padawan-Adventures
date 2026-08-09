import SpriteKit
import UIKit

protocol PitSoundOutWordSceneDelegate: AnyObject {
    func pitSoundOutWordSceneDidWin(starsAwarded: Int)
}

/// SpriteKit sound-out-word pit: blank tiles per grapheme, drag Kam to the right sound.
final class PitSoundOutWordScene: MinigameScene {
    weak var soundOutDelegate: PitSoundOutWordSceneDelegate?

    let soundOutConfig: PitSoundOutWordConfig
    let pitFx: SoundEffectTable
    let floorTileSetLibrary: FloorTileSetLibrary
    let isoConfig: IsometricConfig
    let spriteLibrary: SpriteLibrary
    let playerSpriteConfig: SpriteConfig?

    var engine: GateSoundOutWordEngine
    var placementRNG = SystemRandomNumberGenerator()

    var playerNode: SKNode?
    var playerSprite: AnimatedSpriteNode?
    var playerFacingLeft = false
    var promptNode: SKNode?
    var prompt: MinigameCRTPromptPlate.Prompt?
    var wordGraphemeNodes: [SKNode] = []
    var candidateNodes: [SKNode] = []
    var landedTileNodes: [SKNode] = []
    var isDraggingPlayer = false
    var dragOffset: CGPoint = .zero
    var dragStartPosition: CGPoint = .zero
    var isJumping = false
    var promptContinuationArmed = false

    let padFill = UIColor(red: 0.45, green: 0.28, blue: 0.12, alpha: 1)
    let activeGraphemeColor = UIColor.systemOrange
    let platformCorrectTint = UIColor(red: 0.20, green: 0.65, blue: 0.28, alpha: 1)
    let platformWrongTint = UIColor.systemRed
    let playerFill = UIColor.systemRed

    static let jumpDuration: TimeInterval = 1.0
    static let settleDuration: TimeInterval = 0.18
    static let letterRevealDuration: TimeInterval = 0.25
    /// Duration for the post-miss candidate reshuffle slide.
    static let shuffleDuration: TimeInterval = 0.35
    static let shuffleActionKey = "pitSoundOutShuffle"
    static let playerLibraryID = "player"
    static let playerZ: CGFloat = SceneLayer.player
    static let padsZ: CGFloat = SceneLayer.pads
    static let landedTilesZ: CGFloat = SceneLayer.placedTiles
    static let candidateTilesZ: CGFloat = SceneLayer.trayTiles
    static let promptZ: CGFloat = SceneLayer.overlay
    static let promptWatchdogSeconds: TimeInterval = 10
    static let promptWatchdogKey = "pitSoundOutPromptWatchdog"
    static let promptSoundKey = "pitSoundOutPromptSound"
    static let winSoundActionKey = "pitSoundOutWinSound"
    static let playSymbolActionKey = "pitSoundOutPlaySymbol"
    static let promptPlateName = "wordPrompt"
    static let playSymbolName = "candidatePlaySymbol"
    static let graphemeGlyphName = "candidateGlyph"

    init(
        size: CGSize,
        soundOutConfig: PitSoundOutWordConfig,
        pitFx: SoundEffectTable,
        floorTileSetLibrary: FloorTileSetLibrary,
        isoConfig: IsometricConfig,
        spriteLibrary: SpriteLibrary,
        playerSpriteConfig: SpriteConfig?
    ) {
        self.soundOutConfig = soundOutConfig
        self.pitFx = pitFx
        self.floorTileSetLibrary = floorTileSetLibrary
        self.isoConfig = isoConfig
        self.spriteLibrary = spriteLibrary
        self.playerSpriteConfig = playerSpriteConfig
        self.engine = GateSoundOutWordEngine(
            config: .init(
                choiceCountMin: soundOutConfig.choiceCountMin,
                choiceCountMax: soundOutConfig.choiceCountMax,
                words: soundOutConfig.words,
                graphemes: soundOutConfig.graphemes,
                vocabulary: soundOutConfig.vocabulary
            )
        )
        super.init(size: size)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func buildContent() {
        engine.begin()
        GameLogger.step(.world, "pitSoundOutWord.buildArena") { buildArena() }
        showPrompt()
        playWordSound { [weak self] in self?.beginStep() }
    }

    override func willMove(from view: SKView) {
        removeAction(forKey: Self.promptWatchdogKey)
        removeAction(forKey: Self.promptSoundKey)
        removeAction(forKey: Self.shuffleActionKey)
    }

    override func rebuildLayout() {
        repositionForNewSize()
    }

    func touchesBeganForTesting(at location: CGPoint) {
        touchesBegan(Set([SceneTestTouch(location: location)]), with: nil)
    }

    static func playSymbolTexture(systemName: String, side: CGFloat) -> SKTexture {
        MinigamePlaySoundIcon.texture(systemName: systemName, side: side)
    }
}
