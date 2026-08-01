import Foundation

enum ContinueEligibilityService {
    nonisolated static func isContinueEligible(
        savedWorld: GameWorld?,
        config: WorldGenerationConfig
    ) -> Bool {
        guard let savedWorld else { return false }
        return WorldLoader.isCompatibleSave(savedWorld, with: config)
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
