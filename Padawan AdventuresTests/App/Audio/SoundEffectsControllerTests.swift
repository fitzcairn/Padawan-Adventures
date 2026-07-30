import Foundation
import Testing
@testable import Padawan_Adventures

@MainActor
final class MockSoundEffectPlayer: SoundEffectPlaying {
    private(set) var playCalls: [(trackID: String, volume: Float)] = []
    private(set) var preparedTrackIDs: [String] = []
    private(set) var startedLoops: [(trackID: String, volume: Float)] = []
    private(set) var stoppedLoops: [String] = []
    var activeLoops: Set<String> = []
    var missingTrackIDs: Set<String> = []
    var durations: [String: TimeInterval] = [:]

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
        preparedTrackIDs.append(contentsOf: trackIDs)
    }

    @discardableResult
    func startLoop(trackID: String, volume: Float) -> Bool {
        if missingTrackIDs.contains(trackID) {
            return false
        }
        startedLoops.append((trackID, volume))
        activeLoops.insert(trackID)
        return true
    }

    var startedLoopTrackIDs: [String] {
        startedLoops.map(\.trackID)
    }

    func stopLoop(trackID: String) {
        stoppedLoops.append(trackID)
        activeLoops.remove(trackID)
    }

    func stopAllLoops() {
        for trackID in activeLoops.sorted() {
            stoppedLoops.append(trackID)
        }
        activeLoops.removeAll()
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
        #expect(mock.playCalls.first?.volume == SoundEffectsController.backgroundSFXVolumeScale)
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

    @Test func playUsesConfiguredVolumeForBackgroundSFX() {
        let mock = MockSoundEffectPlayer()
        let controller = SoundEffectsController(player: mock)
        controller.setSoundEffectsVolume(0.4)
        controller.play(trackID: "combat-lightsaber-slash")
        #expect(mock.playCalls.map(\.volume) == [0.4 * SoundEffectsController.backgroundSFXVolumeScale])
    }

    @Test func phoneticTracksPlayAtFullVolume() {
        let mock = MockSoundEffectPlayer()
        let controller = SoundEffectsController(player: mock)
        controller.setSoundEffectsVolume(0.8)
        controller.play(trackID: "sfx_letter_a_name")
        controller.play(trackID: "sfx_word_cat_ca")
        #expect(mock.playCalls.map(\.volume) == [0.8, 0.8])
    }

    @Test func backgroundTracksPlayAtHalfPhoneticVolume() {
        let mock = MockSoundEffectPlayer()
        let controller = SoundEffectsController(player: mock)
        controller.setSoundEffectsVolume(1)
        controller.play(trackID: "combat-lightsaber-slash")
        controller.play(trackID: "pit-jump")
        controller.play(trackID: "gate-letter_match-switch-push")
        #expect(mock.playCalls.map(\.volume) == [0.5, 0.5, 0.5])
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

    @Test func durationReturnsNilForBlankOrUnknown() {
        let mock = MockSoundEffectPlayer()
        let controller = SoundEffectsController(player: mock)
        #expect(controller.duration(of: nil) == nil)
        #expect(controller.duration(of: "") == nil)
        #expect(controller.duration(of: "   ") == nil)
        #expect(controller.duration(of: "missing") == nil)
    }

    @Test func durationReadsFromPlayer() {
        let mock = MockSoundEffectPlayer()
        mock.durations = ["sfx_win": 1.25]
        let controller = SoundEffectsController(player: mock)
        #expect(controller.duration(of: "sfx_win") == 1.25)
    }

    @Test func cueDurationAppliesFallbackAndFloor() {
        let mock = MockSoundEffectPlayer()
        mock.durations = ["short": 0.1, "long": 1.25]
        let controller = SoundEffectsController(player: mock)
        #expect(controller.cueDuration(of: "missing") == 0.7)
        #expect(controller.cueDuration(of: "short") == 0.35)
        #expect(controller.cueDuration(of: "long") == 1.25)
    }

    @Test func prepareForwardsTrackIDs() {
        let mock = MockSoundEffectPlayer()
        let controller = SoundEffectsController(player: mock)
        controller.prepare(trackIDs: ["sfx_win", "sfx_error"])
        #expect(mock.preparedTrackIDs == ["sfx_win", "sfx_error"])
    }

    @Test func startLoopEventReturnsTrackIDAndRecordsStart() {
        let mock = MockSoundEffectPlayer()
        let controller = SoundEffectsController(player: mock)
        let table = SoundEffectTable(events: ["combat_loop": "combat-loop-lightsaber-hum"])
        let trackID = controller.startLoop(event: "combat_loop", from: table)
        #expect(trackID == "combat-loop-lightsaber-hum")
        #expect(mock.startedLoopTrackIDs == ["combat-loop-lightsaber-hum"])
        #expect(mock.activeLoops == ["combat-loop-lightsaber-hum"])
        #expect(mock.startedLoops.first?.volume == SoundEffectsController.backgroundSFXVolumeScale)
    }

    @Test func stopLoopRemovesActiveLoop() {
        let mock = MockSoundEffectPlayer()
        let controller = SoundEffectsController(player: mock)
        let table = SoundEffectTable(events: ["loop": "gate-spelling-loop-arc"])
        let trackID = controller.startLoop(event: "loop", from: table)
        controller.stopLoop(trackID: trackID)
        #expect(mock.activeLoops.isEmpty)
        #expect(mock.stoppedLoops == ["gate-spelling-loop-arc"])
    }

    @Test func disablingSoundEffectsStopsAllLoops() {
        let mock = MockSoundEffectPlayer()
        let controller = SoundEffectsController(player: mock)
        controller.startLoop(trackID: "hum-a")
        controller.startLoop(trackID: "hum-b")
        controller.setSoundEffectsEnabled(false)
        #expect(mock.activeLoops.isEmpty)
        #expect(Set(mock.stoppedLoops) == ["hum-a", "hum-b"])
    }

    @Test func startLoopUnmappedEventIsNoOp() {
        let mock = MockSoundEffectPlayer()
        let controller = SoundEffectsController(player: mock)
        let trackID = controller.startLoop(event: "missing", from: .empty)
        #expect(trackID == nil)
        #expect(mock.startedLoops.isEmpty)
    }

    @Test func isPhoneticTrackRecognizesLetterAndWordCues() {
        #expect(SoundEffectsController.isPhoneticTrack("sfx_letter_a_name"))
        #expect(SoundEffectsController.isPhoneticTrack("sfx_word_gate_ga"))
        #expect(!SoundEffectsController.isPhoneticTrack("combat-loop-lightsaber-hum"))
        #expect(!SoundEffectsController.isPhoneticTrack("pit-jump"))
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
