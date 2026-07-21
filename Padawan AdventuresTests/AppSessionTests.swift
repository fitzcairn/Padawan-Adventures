import Foundation
import Testing
@testable import Padawan_Adventures

struct AppSessionTests {
    @Test func fallbackConfigUsesDenseConnectorCounts() {
        let config = AppSession.fallbackConfig()
        #expect(config.generation.rampCount == 8)
        #expect(config.generation.ladderCount == 8)
        #expect(config.generation.slideCount == 4)
        #expect(config.enemies?.type == "grunt")
        #expect(config.enemies?.spawnChancePerRoom == 0.8)
    }

    @Test func continueIneligibleWhenSaveMissing() {
        let config = AppSession.fallbackConfig()
        #expect(AppSession.isContinueEligible(savedWorld: nil, config: config) == false)
    }

    @Test func continueEligibleWhenDimensionsMatch() {
        let config = AppSession.fallbackConfig()
        let world = TestWorldFactory.emptyFloor(
            width: config.world.width,
            height: config.world.height,
            stories: config.world.stories
        )
        #expect(AppSession.isContinueEligible(savedWorld: world, config: config))
    }

    @Test func continueIneligibleWhenDimensionsDiffer() {
        let config = AppSession.fallbackConfig()
        let world = TestWorldFactory.emptyFloor(width: 4, height: 4, stories: 2)
        #expect(AppSession.isContinueEligible(savedWorld: world, config: config) == false)
    }

    @Test func deleteRemovesSaveFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let service = try GameSaveService(directoryURL: directory)

        let world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        try await service.save(world)
        #expect(try await service.load() != nil)

        try await service.delete()
        #expect(try await service.load() == nil)
    }
}
