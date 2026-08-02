import Foundation
import Testing
@testable import Padawan_Adventures

@MainActor
final class MockSoundEffectPlayer: SoundEffectPlaying {
    private(set) var playCalls: [(trackID: String, volume: Float)] = []
    var missingTrackIDs: Set<String> = []
    var durations: [String: TimeInterval] = [:]
    private(set) var loopTrackIDs: Set<String> = []
    private(set) var prepareCalls: [[String]] = []
    private(set) var fadeOutCalls: [(trackID: String, duration: TimeInterval)] = []
    private(set) var loopDuckScale: Float = 1

    @discardableResult
    func play(trackID: String, volume: Float) -> Bool {
        if missingTrackIDs.contains(trackID) {
            return false
        }
        playCalls.append((trackID, volume))
        return true
    }

    func duration(of trackID: String) -> TimeInterval? {
        durations[trackID]
    }

    func prepare(trackIDs: [String]) {
        prepareCalls.append(trackIDs)
    }

    @discardableResult
    func startLoop(trackID: String, volume: Float) -> Bool {
        if missingTrackIDs.contains(trackID) {
            return false
        }
        loopTrackIDs.insert(trackID)
        playCalls.append((trackID, volume))
        return true
    }

    func stopLoop(trackID: String) {
        loopTrackIDs.remove(trackID)
    }

    func stopAllLoops() {
        loopTrackIDs.removeAll()
    }

    func setLoopDuckScale(_ scale: Float) {
        loopDuckScale = scale
    }

    func fadeOutAndStop(trackID: String, duration: TimeInterval) {
        fadeOutCalls.append((trackID, duration))
        loopTrackIDs.remove(trackID)
    }

    var playedTrackIDs: [String] {
        playCalls.map(\.trackID)
    }
}

@MainActor
struct SoundEffectsControllerTests {
    @Test func playTrackIDRecordsCall() {
        let mock = MockSoundEffectPlayer()
        let controller = SoundEffectsController(player: mock)
        controller.play(trackID: "sfx_boom")
        #expect(mock.playedTrackIDs == ["sfx_boom"])
        #expect(mock.playCalls.first?.volume == 1)
    }

    @Test func playTrackIDIgnoresBlank() {
        let mock = MockSoundEffectPlayer()
        let controller = SoundEffectsController(player: mock)
        controller.play(trackID: "   ")
        #expect(mock.playCalls.isEmpty)
    }

    @Test func playSkipsWhenDisabled() {
        let mock = MockSoundEffectPlayer()
        let controller = SoundEffectsController(player: mock)
        controller.setSoundEffectsEnabled(false)
        controller.play(trackID: "sfx_boom")
        #expect(mock.playCalls.isEmpty)
    }

    @Test func playUsesConfiguredVolume() {
        let mock = MockSoundEffectPlayer()
        let controller = SoundEffectsController(player: mock)
        controller.setSoundEffectsVolume(0.4)
        controller.play(trackID: "sfx_boom")
        #expect(mock.playCalls.map(\.volume) == [0.4])
    }

    @Test func playEventResolvesFromTable() {
        let mock = MockSoundEffectPlayer()
        let controller = SoundEffectsController(player: mock)
        let table = SoundEffectTable(events: ["move": "sfx_player_move", "pit": "sfx_pit"])
        controller.play(event: "move", from: table)
        controller.play(event: "pit", from: table)
        #expect(mock.playedTrackIDs == ["sfx_player_move", "sfx_pit"])
    }

    @Test func playCommonUsesConfiguredTable() {
        let mock = MockSoundEffectPlayer()
        let controller = SoundEffectsController(player: mock)
        controller.configure(commonFx: SoundEffectTable(events: [
            "win": "sfx_win",
            "error": "sfx_error",
        ]))
        controller.playCommon(event: "win")
        controller.playCommon(event: "error")
        controller.playCommon(event: "missing")
        #expect(mock.playedTrackIDs == ["sfx_win", "sfx_error"])
    }

    @Test func playCommonOverrideBeatsSharedTable() {
        let mock = MockSoundEffectPlayer()
        let controller = SoundEffectsController(player: mock)
        controller.configure(commonFx: SoundEffectTable(events: ["win": "sfx_win"]))
        controller.playCommon(event: "win", override: "sfx_win_alt")
        controller.playCommon(event: "win", override: "   ")
        controller.playCommon(event: "win", override: nil)
        #expect(mock.playedTrackIDs == ["sfx_win_alt", "sfx_win", "sfx_win"])
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
        #expect(mock.playedTrackIDs == ["sfx_a", "sfx_b", "sfx_c"])
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
            "gate_opened": "sfx_gate_opened",
            "pickup": "sfx_pickup",
        ])
        let overrides = SoundEffectTable(events: [
            "gate_opened": "sfx_gate_opened_alt",
        ])
        let merged = base.merging(overrides)
        #expect(merged.trackID(for: "gate_opened") == "sfx_gate_opened_alt")
        #expect(merged.trackID(for: "pickup") == "sfx_pickup")
    }

    @Test func mergingEmptyOverridesIsIdentity() {
        let base = SoundEffectTable(events: ["gate_opened": "sfx_gate_opened"])
        #expect(base.merging(.empty) == base)
    }
}
