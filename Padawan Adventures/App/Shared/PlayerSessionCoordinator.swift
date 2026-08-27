import Foundation

extension AppSession {
    func bindPlayer(name: String) async throws {
        // Player names are user data and deliberately kept out of the log.
        try await GameLogger.step(.session, "bindPlayer") {
            let trimmed = PlayerStateStore.normalizedName(name)
            let playerSaveService = try await playerStore.makeSaveService(for: trimmed)
            let state: PlayerGameState
            do {
                state = try await playerStore.loadState(for: trimmed)
            } catch PlayerStateError.unsupportedVersion {
                GameLogger.mark(.session, "incompatible save format; starting a new game")
                state = try await playerStore.resetIncompatibleState(
                    for: trimmed,
                    health: playerConfig.startingHealth,
                    energy: playerConfig.startingEnergy
                )
                do {
                    try await playerSaveService.delete()
                } catch {
                    GameLogger.error(.session, "could not delete mid-run save: \(error)")
                }
            }

            currentPlayerName = trimmed
            playerState = state
            saveService = playerSaveService
            audioPreferences.apply(state.settings)

            if let lastLevel = state.lastLevelStarted {
                GameLogger.mark(.session, "restoring last level '\(lastLevel)'")
                do {
                    try selectLevel(resourceName: lastLevel)
                } catch {
                    GameLogger.error(
                        .session,
                        "could not restore '\(lastLevel)': \(error); keeping bootstrap level"
                    )
                }
            }

            await refreshContinueEligibility()
        }
    }

    /// Copies the live Settings values into the bound player's persisted state.
    func persistCurrentSettings() async {
        guard playerState != nil else { return }
        playerState?.settings = audioPreferences.snapshot
        await persistPlayerState()
    }

    func createAndBindPlayer(name: String) async throws {
        let trimmed = PlayerStateStore.normalizedName(name)
        let initial = PlayerGameState(
            health: playerConfig.startingHealth,
            energy: playerConfig.startingEnergy
        )
        try await playerStore.createPlayer(name: trimmed, initialState: initial)
        try await bindPlayer(name: trimmed)
    }

    func deletePlayer(name: String) async throws {
        let trimmed = PlayerStateStore.normalizedName(name)
        try await playerStore.deletePlayer(name: trimmed)
        if currentPlayerName == trimmed {
            currentPlayerName = nil
            playerState = nil
            hasCompatibleSave = false
        }
    }

    func persistPlayerState() async {
        guard let name = currentPlayerName, let state = playerState else { return }
        try? await playerStore.saveState(state, for: name)
    }

    func syncVitals(from world: GameWorld) async {
        guard playerState != nil else { return }
        playerState?.syncVitals(from: world)
        await persistPlayerState()
    }

    /// Starts a fresh game: empty inventory, zero stars, default vitals, no mid-run save.
    func beginNewGame() async {
        await GameLogger.step(.session, "beginNewGame") {
            guard var state = playerState else {
                GameLogger.error(.session, "beginNewGame with no bound player; ignoring")
                return
            }
            state.resetForNewGame(
                health: playerConfig.startingHealth,
                energy: playerConfig.startingEnergy
            )
            playerState = state
            pendingLevelSelectCelebration = nil
            await persistPlayerState()
            do {
                try await saveService.delete()
            } catch {
                GameLogger.error(.session, "could not delete mid-run save: \(error)")
            }
            await refreshContinueEligibility()
        }
    }
}
