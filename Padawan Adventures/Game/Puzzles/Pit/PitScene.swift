import SpriteKit
import UIKit

protocol PitSceneDelegate: AnyObject {
    func pitSceneDidSelectWord(_ word: String)
    func pitSceneDidUpdateSolvedCount(_ count: Int)
    func pitSceneDidWin(word: String, starsAwarded: Int)
}

/// SpriteKit pit puzzle: side pads, hoppable letter floor tiles.
final class PitScene: MinigameScene {
    weak var pitDelegate: PitSceneDelegate?

    let puzzleConfig: PitPuzzleConfig
    let pitFx: SoundEffectTable
    let floorTileSetLibrary: FloorTileSetLibrary
    /// Same isometric footprint as the world engine (`app.yaml` display tiles).
    let isoConfig: IsometricConfig
    let spriteLibrary: SpriteLibrary
    let playerSpriteConfig: SpriteConfig?

    var engine: PitMinigameEngine
    var letterNodes: [UUID: SKNode] = [:]
    var platformNodes: [UUID: SKSpriteNode] = [:]
    var playerNode: SKNode?
    var playerSprite: AnimatedSpriteNode?
    var playerFacingLeft = false
    var leftPadRect: CGRect = .zero
    var rightPadRect: CGRect = .zero
    var playFieldRect: CGRect = .zero
    var isJumping = false
    var placementRNG = SystemRandomNumberGenerator()

    let padFill = UIColor(red: 0.45, green: 0.28, blue: 0.12, alpha: 1)
    let platformCorrectTint = UIColor(red: 0.20, green: 0.65, blue: 0.28, alpha: 1)
    let platformWrongFlash = UIColor.systemYellow
    let playerFill = UIColor.systemRed

    static let jumpDuration: TimeInterval = 1.0
    static let playerLibraryID = "player"
    /// Above pads (z≈1) and letter platforms (z≈10).
    static let playerZ: CGFloat = SceneLayer.player
    static let connectedSoundActionKey = "pitConnectedSound"
    static let winSoundActionKey = "pitWinSound"
    /// Extra margin around the letter relative to font size (each side).
    static let letterPaddingRatio: CGFloat = 0.45
    /// Platform sprites are drawn this much larger than the letter+padding box.
    static let platformScale: CGFloat = 1.75
    /// Side pads are a 2×2 block of level floor tiles.
    /// Keep jump platforms clear of the top-center HUD word (44pt) + margin.
    static let hudWordClearance: CGFloat = 72
    /// Shrinks platform size across placement retries when the field is overcrowded.
    var layoutScale: CGFloat = 1.0

    init(
        size: CGSize,
        puzzleConfig: PitPuzzleConfig,
        pitFx: SoundEffectTable,
        floorTileSetLibrary: FloorTileSetLibrary,
        isoConfig: IsometricConfig,
        spriteLibrary: SpriteLibrary,
        playerSpriteConfig: SpriteConfig?
    ) {
        self.puzzleConfig = puzzleConfig
        self.pitFx = pitFx
        self.floorTileSetLibrary = floorTileSetLibrary
        self.isoConfig = isoConfig
        self.spriteLibrary = spriteLibrary
        self.playerSpriteConfig = playerSpriteConfig
        self.engine = PitMinigameEngine(config: .init(from: puzzleConfig))
        super.init(size: size)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func buildContent() {
        engine.begin()
        pitDelegate?.pitSceneDidSelectWord(engine.targetWord)
        pitDelegate?.pitSceneDidUpdateSolvedCount(0)
        GameLogger.step(.world, "pit.buildPuzzle") { buildPuzzle() }
        playWordSound()
    }

    override func willMove(from view: SKView) {
        GameLogger.mark(.world, "pit.willMove teardown")
        removeAction(forKey: Self.connectedSoundActionKey)
        removeAction(forKey: Self.winSoundActionKey)
        let trackID = engine.targetSoundTrackID
        if !trackID.isEmpty {
            SoundEffectsController.shared.fadeOutAndStop(trackID: trackID)
        }
    }

    override func rebuildLayout() {
        rebuildLayoutPreservingLetters()
    }
}

final class SceneTestTouch: UITouch {
    let location: CGPoint

    init(location: CGPoint) {
        self.location = location
        super.init()
    }

    override func location(in view: UIView?) -> CGPoint {
        location
    }
}
