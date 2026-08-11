import Foundation

extension AppSession {
    func selectLevel(resourceName: String) throws {
        try GameLogger.step(.session, "selectLevel(\(resourceName))") {
            let loaded = try WorldLoader.loadConfigAndLevelFromBundle(
                levelNamed: resourceName,
                levelSubdirectory: LevelCatalog.subdirectory
            )
            try loaded.config.validate()
            appConfig = loaded.config
            applySelectedLevel(loaded.level, resourceName: resourceName)
        }
    }

    func applySelectedLevel(_ level: LevelConfig, resourceName: String?) {
        GameLogger.mark(
            .session,
            """
            applySelectedLevel '\(level.name)' \
            (combat: \(level.combat.minigames.map(\.kind.rawValue).joined(separator: "/")), \
            gate: \(level.gate.minigames.count) minigames)
            """
        )
        selectedLevel = level
        selectedLevelName = Strings.text(level.name)
        selectedLevelResourceName = resourceName
        selectedLevelArtifact = level.artifact
        selectedLevelMusic = level.music
        selectedPitConfig = level.pit
        selectedGateConfig = level.gate
        selectedCombatConfig = level.combat
    }

    func markLevelStarted(resourceName: String) async {
        playerState?.markLevelStarted(resourceName)
        selectedLevelResourceName = resourceName
        await persistPlayerState()
    }

    func markLevelCompleted(resourceName: String) async {
        let wasCompleted = playerState?.levels[resourceName]?.completed == true
        playerState?.markLevelCompleted(resourceName, artifact: selectedLevelArtifact)
        if !wasCompleted {
            pendingLevelSelectCelebration = resourceName
        }
        await persistPlayerState()
    }

    /// Returns and clears the pending level-select unlock celebration, if any.
    func consumeLevelSelectCelebration() -> String? {
        let resourceName = pendingLevelSelectCelebration
        pendingLevelSelectCelebration = nil
        return resourceName
    }

    var isDadModeUnlocked: Bool {
        playerState?.dadModeUnlocked ?? false
    }

    @discardableResult
    func unlockDadMode() async -> Bool {
        guard var state = playerState else { return false }
        state.dadModeUnlocked = true
        playerState = state
        await persistPlayerState()
        return true
    }

    func hasSeenMinigameTutorial(_ key: String) -> Bool {
        playerState?.hasSeenMinigameTutorial(key) ?? false
    }

    /// Records the tutorial as seen in memory immediately, then persists.
    /// Synchronous memory update so a SwiftUI rebuild cannot re-show the demo
    /// before an async Task lands.
    func markMinigameTutorialSeen(_ key: String) {
        guard var state = playerState,
              state.markMinigameTutorialSeen(key) else { return }
        playerState = state
        Task { await persistPlayerState() }
    }

    var hasSeenWorldTutorial: Bool {
        playerState?.seenWorldTutorial ?? false
    }

    func markWorldTutorialSeen() async {
        guard var state = playerState, !state.seenWorldTutorial else { return }
        state.seenWorldTutorial = true
        playerState = state
        await persistPlayerState()
    }

    /// Grants artifacts / completion for all catalog levels before `resourceName`, clears Dad mode, persists.
    func applyDadModeProgression(to resourceName: String) async {
        guard var state = playerState else { return }
        let ordered = LevelCatalog.loadFromBundle().map(\.resourceName)
        var artifactsByResource: [String: String] = [:]
        for name in ordered {
            if let level = try? LevelConfig.loadFromBundle(
                named: name,
                subdirectory: LevelCatalog.subdirectory
            ) {
                artifactsByResource[name] = level.artifact
            }
        }
        state.applyProgressionJump(
            upTo: resourceName,
            orderedLevels: ordered,
            artifactsByResource: artifactsByResource
        )
        playerState = state
        await persistPlayerState()
    }

    func resetLevelStarsCurrent(resourceName: String) async {
        guard playerState != nil else { return }
        playerState?.resetLevelStarsCurrent(resourceName)
        await persistPlayerState()
    }

    func addLevelStar(resourceName: String) async {
        await addLevelStars(resourceName: resourceName, count: 1)
    }

    func addLevelStars(resourceName: String, count: Int) async {
        guard playerState != nil, count > 0 else { return }
        playerState?.addLevelStars(resourceName, count: count)
        await persistPlayerState()
    }

    @discardableResult
    func finalizeLevelStars(resourceName: String) async -> LevelStarsFinalizeResult? {
        guard var state = playerState else { return nil }
        let result = state.finalizeLevelStars(resourceName)
        playerState = state
        await persistPlayerState()
        return result
    }

    func recordStat(_ update: (inout PlayerStats) -> Void) async {
        guard var state = playerState else { return }
        update(&state.stats)
        playerState = state
        await persistPlayerState()
    }
}
