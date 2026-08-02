import Foundation

enum ContinueDestination: Equatable, Sendable {
    /// Resume an in-progress mid-run world save (player left mid-level).
    case resumeSave
    /// Return to the planet map (player last left from level select, e.g. after a win).
    case levelSelect
}

enum ContinueEligibilityService {
    nonisolated static func isContinueEligible(
        savedWorld: GameWorld?,
        config: WorldGenerationConfig
    ) -> Bool {
        guard let savedWorld else { return false }
        return WorldLoader.isCompatibleSave(savedWorld, with: config)
    }

    /// Campaign progress that should keep CONTINUE available after a mid-run save is cleared
    /// (e.g. after beating a level).
    nonisolated static func hasCampaignProgress(_ state: PlayerGameState?) -> Bool {
        guard let state else { return false }
        if state.lastLevelStarted != nil { return true }
        if state.totalStars > 0 { return true }
        if !state.inventory.artifacts.isEmpty { return true }
        return state.levels.contains { _, progress in
            progress.started
                || progress.completed
                || progress.starsEarned > 0
                || progress.starsCurrent > 0
        }
    }

    nonisolated static func shouldShowContinue(
        hasCompatibleSave: Bool,
        playerState: PlayerGameState?
    ) -> Bool {
        hasCompatibleSave || hasCampaignProgress(playerState)
    }

    nonisolated static func continueDestination(
        hasCompatibleSave: Bool,
        playerState: PlayerGameState?
    ) -> ContinueDestination? {
        guard shouldShowContinue(hasCompatibleSave: hasCompatibleSave, playerState: playerState)
        else { return nil }
        return hasCompatibleSave ? .resumeSave : .levelSelect
    }

    static func probeCompatibleSave(
        saveService: GameSaveService,
        config: WorldGenerationConfig
    ) async -> Bool {
        do {
            let saved = try await saveService.load()
            return isContinueEligible(savedWorld: saved, config: config)
        } catch {
            return false
        }
    }
}

extension AppSession {
    nonisolated static func isContinueEligible(
        savedWorld: GameWorld?,
        config: WorldGenerationConfig
    ) -> Bool {
        ContinueEligibilityService.isContinueEligible(savedWorld: savedWorld, config: config)
    }

    var shouldShowContinue: Bool {
        ContinueEligibilityService.shouldShowContinue(
            hasCompatibleSave: hasCompatibleSave,
            playerState: playerState
        )
    }

    var continueDestination: ContinueDestination? {
        ContinueEligibilityService.continueDestination(
            hasCompatibleSave: hasCompatibleSave,
            playerState: playerState
        )
    }

    func refreshContinueEligibility() async {
        guard currentPlayerName != nil else {
            hasCompatibleSave = false
            return
        }

        var generation = generationConfig
        if let lastLevel = playerState?.lastLevelStarted {
            if let loaded = try? WorldLoader.loadConfigAndLevelFromBundle(
                levelNamed: lastLevel,
                levelSubdirectory: LevelCatalog.subdirectory
            ) {
                generation = .compose(app: loaded.config, level: loaded.level)
            }
        }

        hasCompatibleSave = await ContinueEligibilityService.probeCompatibleSave(
            saveService: saveService,
            config: generation
        )
    }
}
