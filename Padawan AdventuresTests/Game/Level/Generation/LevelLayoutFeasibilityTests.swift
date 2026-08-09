import Testing
@testable import Padawan_Adventures

/// The packed room placer stops early when it runs out of space, so a level can
/// silently ship fewer rooms than its config asks for. Guard the shipped configs.
struct LevelLayoutFeasibilityTests {
    @Test func everyShippedLevelPacksItsFullRoomCount() throws {
        for descriptor in LevelCatalog.loadFromBundle() {
            let level = try LevelConfig.loadFromBundle(
                named: descriptor.resourceName,
                subdirectory: LevelCatalog.subdirectory
            )
            for seed: UInt64 in [1, 7, 42, 99, 1234] {
                var rng = SeededGenerator(seed: seed)
                let rooms = ProceduralGenerator().placePackedRooms(
                    count: level.roomCount,
                    minSize: level.room.minRoomSize,
                    maxSize: level.room.maxRoomSize,
                    width: level.width,
                    height: level.height,
                    rng: &rng
                )
                #expect(
                    rooms.count == level.roomCount,
                    "\(descriptor.resourceName) packed \(rooms.count)/\(level.roomCount) rooms (seed \(seed))"
                )
            }
        }
    }
}
