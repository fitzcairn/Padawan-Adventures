import Foundation
import Testing
@testable import Padawan_Adventures

@MainActor
final class MockSoundEffectPlayer: SoundEffectPlaying {
    private(set) var playCalls: [String] = []
    var missingTrackIDs: Set<String> = []

    @discardableResult
    func play(trackID: String) -> Bool {
        if missingTrackIDs.contains(trackID) {
            return false
        }
        playCalls.append(trackID)
        return true
    }
}

@MainActor
struct SoundEffectsControllerTests {
    @Test func playTrackIDRecordsCall() {
        let mock = MockSoundEffectPlayer()
        let controller = SoundEffectsController(player: mock)
        controller.play(trackID: "sfx_boom")
        #expect(mock.playCalls == ["sfx_boom"])
    }

    @Test func playTrackIDIgnoresBlank() {
        let mock = MockSoundEffectPlayer()
        let controller = SoundEffectsController(player: mock)
        controller.play(trackID: "   ")
        #expect(mock.playCalls.isEmpty)
    }

    @Test func playEventResolvesFromTable() {
        let mock = MockSoundEffectPlayer()
        let controller = SoundEffectsController(player: mock)
        let table = SoundEffectTable(events: ["move": "sfx_player_move", "pit": "sfx_pit"])
        controller.play(event: "move", from: table)
        controller.play(event: "pit", from: table)
        #expect(mock.playCalls == ["sfx_player_move", "sfx_pit"])
    }

    @Test func playEventIgnoresUnknownKey() {
        let mock = MockSoundEffectPlayer()
        let controller = SoundEffectsController(player: mock)
        let table = SoundEffectTable(events: ["move": "sfx_player_move"])
        controller.play(event: "unknown", from: table)
        #expect(mock.playCalls.isEmpty)
    }

    @Test func playEventIgnoresMissingAsset() {
        let mock = MockSoundEffectPlayer()
        mock.missingTrackIDs = ["sfx_missing"]
        let controller = SoundEffectsController(player: mock)
        let table = SoundEffectTable(events: ["boom": "sfx_missing"])
        controller.play(event: "boom", from: table)
        #expect(mock.playCalls.isEmpty)
    }

    @Test func concurrentPlaysOverlap() {
        let mock = MockSoundEffectPlayer()
        let controller = SoundEffectsController(player: mock)
        controller.play(trackID: "sfx_a")
        controller.play(trackID: "sfx_b")
        controller.play(trackID: "sfx_c")
        #expect(mock.playCalls == ["sfx_a", "sfx_b", "sfx_c"])
    }
}

struct SoundEffectTableTests {
    @Test func trackIDTrimsAndRejectsEmpty() {
        let table = SoundEffectTable(events: [
            "move": "  sfx_player_move  ",
            "blank": "   ",
        ])
        #expect(table.trackID(for: "move") == "sfx_player_move")
        #expect(table.trackID(for: "blank") == nil)
        #expect(table.trackID(for: "missing") == nil)
    }

    @Test func mergingOverridesPerEvent() {
        let base = SoundEffectTable(events: [
            "wall_destroyed": "sfx_wall_destroyed",
            "gate_opened": "sfx_gate_opened",
        ])
        let overrides = SoundEffectTable(events: [
            "wall_destroyed": "sfx_wall_destroyed_alt",
        ])
        let merged = base.merging(overrides)
        #expect(merged.trackID(for: "wall_destroyed") == "sfx_wall_destroyed_alt")
        #expect(merged.trackID(for: "gate_opened") == "sfx_gate_opened")
    }

    @Test func mergingEmptyOverridesIsIdentity() {
        let base = SoundEffectTable(events: ["gate_opened": "sfx_gate_opened"])
        #expect(base.merging(.empty) == base)
    }
}
