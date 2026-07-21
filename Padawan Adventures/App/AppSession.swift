import Foundation

/// Shared bootstrap state loaded before the menu appears.
@MainActor
final class AppSession {
    let seedConfig: WorldSeedConfig
    let saveService: GameSaveService
    private(set) var hasCompatibleSave: Bool

    init(seedConfig: WorldSeedConfig, saveService: GameSaveService, hasCompatibleSave: Bool) {
        self.seedConfig = seedConfig
        self.saveService = saveService
        self.hasCompatibleSave = hasCompatibleSave
    }

    nonisolated static func fallbackConfig() -> WorldSeedConfig {
        WorldSeedConfig(
            version: 1,
            seed: 42,
            world: .init(width: 100, height: 100, stories: 2),
            generation: .init(
                algorithm: "rooms_doors",
                roomCount: 100,
                corridorWidth: 2,
                minRoomSize: 4,
                maxRoomSize: 12,
                pitChance: 0.05,
                wallDestructibleChance: 0.2,
                rampCount: 2,
                ladderCount: 2,
                slideCount: 1,
                doorCount: 4
            ),
            display: .init(tileWidth: 40, tileHeight: 40),
            player: .init(letter: "P", spawn: nil),
            extensions: nil
        )
    }

    /// Loads seed config, save service, and continue eligibility.
    static func loadResources() async -> AppSession {
        let seedConfig: WorldSeedConfig
        do {
            let loaded = try WorldLoader.loadConfigFromBundle()
            try loaded.validate()
            seedConfig = loaded
        } catch {
            seedConfig = fallbackConfig()
        }

        let saveService: GameSaveService
        if let primary = try? GameSaveService() {
            saveService = primary
        } else {
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("PadawanAdventures", isDirectory: true)
            try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            saveService = try! GameSaveService(directoryURL: temp)
        }

        let hasCompatibleSave = await Self.probeCompatibleSave(
            saveService: saveService,
            config: seedConfig
        )

        return AppSession(
            seedConfig: seedConfig,
            saveService: saveService,
            hasCompatibleSave: hasCompatibleSave
        )
    }

    nonisolated static func isContinueEligible(savedWorld: GameWorld?, config: WorldSeedConfig) -> Bool {
        guard let savedWorld else { return false }
        return WorldLoader.isCompatibleSave(savedWorld, with: config)
    }

    func refreshContinueEligibility() async {
        hasCompatibleSave = await Self.probeCompatibleSave(
            saveService: saveService,
            config: seedConfig
        )
    }

    private static func probeCompatibleSave(
        saveService: GameSaveService,
        config: WorldSeedConfig
    ) async -> Bool {
        do {
            let saved = try await saveService.load()
            return isContinueEligible(savedWorld: saved, config: config)
        } catch {
            return false
        }
    }
}

enum GameLaunchMode: Equatable, Sendable {
    case continueSave
    case newGame
}
