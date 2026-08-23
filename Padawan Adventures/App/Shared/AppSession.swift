import Foundation
import SpriteKit
import UIKit

/// Shared bootstrap state loaded before the menu appears.
@MainActor
final class AppSession {
    var memoryWarningObserver: NSObjectProtocol?
    var appConfig: AppConfig
    /// Full selected level (map size, generation, floors, puzzles, music, …).
    var selectedLevel: LevelConfig
    var selectedLevelName: String
    var selectedLevelResourceName: String?
    /// SF Symbol name awarded to inventory when this level is completed.
    var selectedLevelArtifact: String
    /// Raw level `music:` value for the selected level.
    var selectedLevelMusic: String?
    /// Pit minigame variants + weights for the selected level.
    var selectedPitConfig: PitConfig
    /// Gate config (host FX + minigames list) for the selected level.
    var selectedGateConfig: GateConfig
    /// Combat minigame variants + weights for the selected level.
    var selectedCombatConfig: CombatConfig
    /// Shared without-replacement word/grapheme draws for the current level run.
    var vocabularySampler: LevelVocabularySampler

    /// App + level knobs for procedural generation / save-size checks.
    var generationConfig: WorldGenerationConfig {
        .compose(app: appConfig, level: selectedLevel)
    }
    let playerConfig: PlayerConfig
    let enemyConfig: EnemyConfig
    let itemsConfig: ItemsConfig
    let npcsConfig: NpcsConfig
    let playerStore: PlayerStateStore
    var saveService: GameSaveService
    var hasCompatibleSave: Bool
    var currentPlayerName: String?
    var playerState: PlayerGameState?
    let audioPreferences: AudioPreferences
    /// Session-scoped sprite animation cache (sheets sliced once per process).
    let spriteLibrary: SpriteLibrary
    /// Session-scoped cache of the active level's baked floor tile set.
    let floorTileSetLibrary: FloorTileSetLibrary
    /// Session-scoped cache of the active level's baked letter glyph set.
    let letterSpriteSetLibrary: LetterSpriteSetLibrary
    /// Session-scoped cache of the active level's baked pit platform tile set.
    let pitSpriteSetLibrary: PitSpriteSetLibrary
    /// Session-scoped cache of the active level's baked world gate wall sprites.
    let gateSpriteSetLibrary: GateSpriteSetLibrary
    /// Session-scoped still background cache (screen BGs at game open).
    let backgroundLibrary: BackgroundLibrary
    /// Session-scoped cutscene movie, preloaded so NEW GAME can start playback immediately.
    let cutsceneVideo: CutsceneVideo
    /// Resource name of a level first-completed this session; level select consumes it for unlock FX.
    var pendingLevelSelectCelebration: String? = nil

    init(
        appConfig: AppConfig,
        selectedLevel: LevelConfig = .fallback,
        selectedLevelName: String? = nil,
        selectedLevelResourceName: String? = nil,
        selectedLevelArtifact: String? = nil,
        selectedLevelMusic: String? = nil,
        selectedPitConfig: PitConfig? = nil,
        selectedGateConfig: GateConfig? = nil,
        selectedCombatConfig: CombatConfig? = nil,
        playerConfig: PlayerConfig? = nil,
        enemyConfig: EnemyConfig? = nil,
        itemsConfig: ItemsConfig? = nil,
        npcsConfig: NpcsConfig? = nil,
        playerStore: PlayerStateStore,
        saveService: GameSaveService,
        hasCompatibleSave: Bool = false,
        currentPlayerName: String? = nil,
        playerState: PlayerGameState? = nil,
        audioPreferences: AudioPreferences? = nil,
        spriteLibrary: SpriteLibrary? = nil,
        floorTileSetLibrary: FloorTileSetLibrary? = nil,
        letterSpriteSetLibrary: LetterSpriteSetLibrary? = nil,
        pitSpriteSetLibrary: PitSpriteSetLibrary? = nil,
        gateSpriteSetLibrary: GateSpriteSetLibrary? = nil,
        backgroundLibrary: BackgroundLibrary? = nil,
        cutsceneVideo: CutsceneVideo? = nil
    ) {
        self.appConfig = appConfig
        self.selectedLevel = selectedLevel
        self.selectedLevelName = selectedLevelName ?? Strings.text(selectedLevel.name)
        self.selectedLevelResourceName = selectedLevelResourceName
        self.selectedLevelArtifact = selectedLevelArtifact ?? selectedLevel.artifact
        self.selectedLevelMusic = selectedLevelMusic ?? selectedLevel.music
        self.selectedPitConfig = selectedPitConfig ?? selectedLevel.pit
        self.selectedGateConfig = selectedGateConfig ?? selectedLevel.gate
        self.selectedCombatConfig = selectedCombatConfig ?? selectedLevel.combat
        self.vocabularySampler = LevelVocabularySampler(pool: selectedLevel.vocabulary)
        // Default-argument expressions are nonisolated; resolve MainActor defaults in-body.
        self.playerConfig = playerConfig ?? .fallback
        self.enemyConfig = enemyConfig ?? .fallback
        self.itemsConfig = itemsConfig ?? .fallback
        self.npcsConfig = npcsConfig ?? .fallback
        self.playerStore = playerStore
        self.saveService = saveService
        self.hasCompatibleSave = hasCompatibleSave
        self.currentPlayerName = currentPlayerName
        self.playerState = playerState
        self.audioPreferences = audioPreferences ?? .shared
        self.spriteLibrary = spriteLibrary ?? SpriteLibrary()
        self.floorTileSetLibrary = floorTileSetLibrary ?? FloorTileSetLibrary()
        self.letterSpriteSetLibrary = letterSpriteSetLibrary ?? LetterSpriteSetLibrary()
        self.pitSpriteSetLibrary = pitSpriteSetLibrary ?? PitSpriteSetLibrary()
        self.gateSpriteSetLibrary = gateSpriteSetLibrary ?? GateSpriteSetLibrary()
        self.backgroundLibrary = backgroundLibrary ?? BackgroundLibrary()
        self.cutsceneVideo = cutsceneVideo ?? CutsceneVideo()
    }
}

enum GameLaunchMode: Hashable, Sendable {
    case continueSave
    case newGame
}
