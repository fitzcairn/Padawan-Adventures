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
    private(set) var fadeOutAllCalls: [TimeInterval] = []
    private(set) var loopDuckScale: Float = 1
    private(set) var voiceOverCalls: [(trackID: String, crossfade: TimeInterval)] = []
    private(set) var fadeOutVoiceOverCalls: [TimeInterval] = []

    @discardableResult
    func play(trackID: String, volume: Float) -> Bool {
        if missingTrackIDs.contains(trackID) {
            return false
        }
        playCalls.append((trackID, volume))
        return true
    }

    @discardableResult
    func playVoiceOver(trackID: String, volume: Float, crossfade: TimeInterval) -> Bool {
        if missingTrackIDs.contains(trackID) {
            return false
        }
        voiceOverCalls.append((trackID, crossfade))
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

    func fadeOutVoiceOver(duration: TimeInterval) {
        fadeOutVoiceOverCalls.append(duration)
    }

    func fadeOutAndStopAll(duration: TimeInterval) {
        fadeOutAllCalls.append(duration)
        loopTrackIDs.removeAll()
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
        // Non-phonetic FX sit below phonetic cues in the mix.
        #expect(
            mock.playCalls.first?.volume == SoundEffectsController.backgroundSFXVolumeScale
        )
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
        #expect(
            mock.playCalls.map(\.volume)
                == [0.4 * SoundEffectsController.backgroundSFXVolumeScale]
        )
    }

    /// The mix hierarchy the scale constants exist to produce: phonetic cues are the
    /// loudest, ambience/action FX sit below them, and saber clips below that.
    @Test func phoneticCuesOutrankBackgroundAndLightsaberFX() {
        let mock = MockSoundEffectPlayer()
        let controller = SoundEffectsController(player: mock)
        // Phonetic playback ducks BGM; absorb it so the shared controller is untouched.
        controller.phoneticCueDuckHandler = { _ in }
        controller.play(trackID: "sfx_letter_a_name")
        controller.play(trackID: "sfx_boom")
        controller.play(trackID: "lightsaber-hum")
        let volumes = mock.playCalls.map(\.volume)
        #expect(volumes.count == 3)
        #expect(volumes[0] > volumes[1])
        #expect(volumes[1] > volumes[2])
    }

    /// Combat widens the phonetic-vs-FX gap without changing the ordering.
    @Test func combatMixWidensPhoneticSeparation() {
        func volumes(combat: Bool) -> (phonetic: Float, fx: Float) {
            let mock = MockSoundEffectPlayer()
            let controller = SoundEffectsController(player: mock)
            controller.phoneticCueDuckHandler = { _ in }
            controller.setSoundEffectsVolume(0.5)
            controller.setCombatMixActive(combat)
            controller.play(trackID: "sfx_word_bat")
            controller.play(trackID: "sfx_boom")
            return (mock.playCalls[0].volume, mock.playCalls[1].volume)
        }

        let calm = volumes(combat: false)
        let combat = volumes(combat: true)
        #expect(combat.phonetic > calm.phonetic)
        #expect(combat.fx < calm.fx)
        #expect(combat.phonetic / combat.fx > calm.phonetic / calm.fx)
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

    @Test func fadeOutAndStopAllForwardsDefaultDuration() {
        let mock = MockSoundEffectPlayer()
        let controller = SoundEffectsController(player: mock)
        controller.fadeOutAndStopAll()
        #expect(mock.fadeOutAllCalls == [SoundEffectsController.defaultOneShotFadeOutSeconds])
    }

    @Test func gameplaySuppressionBlocksMinigameSFXButAllowsTutorialVO() {
        let mock = MockSoundEffectPlayer()
        let controller = SoundEffectsController(player: mock)
        controller.phoneticCueDuckHandler = { _ in }
        controller.setGameplaySFXSuppressed(true)
        controller.play(trackID: "sfx_combat_start")
        controller.play(trackID: "sfx_word_bat")
        controller.play(trackID: "sfx_ui_tutorial_deflect")
        #expect(mock.playedTrackIDs == ["sfx_ui_tutorial_deflect"])

        let loopID = controller.startLoop(
            event: "combat_loop",
            from: SoundEffectTable(events: ["combat_loop": "sfx_combat_loop"])
        )
        #expect(loopID == nil)
        #expect(mock.loopTrackIDs.isEmpty)

        controller.setGameplaySFXSuppressed(false)
        controller.play(trackID: "sfx_combat_start")
        #expect(mock.playedTrackIDs == ["sfx_ui_tutorial_deflect", "sfx_combat_start"])
    }

    /// Catalog voice-over goes to the exclusive channel; everything else overlaps as before.
    @Test func uiVoiceOverPlaysOnTheExclusiveChannel() {
        let mock = MockSoundEffectPlayer()
        let controller = SoundEffectsController(player: mock)
        controller.phoneticCueDuckHandler = { _ in }
        controller.play(trackID: "sfx_ui_level_tython")
        controller.play(trackID: "sfx_ui_level_dagobah")
        controller.play(trackID: "sfx_boom")
        controller.play(trackID: "sfx_word_bat")

        #expect(
            mock.voiceOverCalls.map(\.trackID)
                == ["sfx_ui_level_tython", "sfx_ui_level_dagobah"]
        )
        #expect(
            mock.voiceOverCalls.allSatisfy {
                $0.crossfade == SoundEffectsController.voiceOverCrossfadeSeconds
            }
        )
    }

    @Test func fadeOutVoiceOverForwardsDefaultDuration() {
        let mock = MockSoundEffectPlayer()
        let controller = SoundEffectsController(player: mock)
        controller.fadeOutVoiceOver()
        controller.fadeOutVoiceOver(duration: -1)
        #expect(
            mock.fadeOutVoiceOverCalls
                == [SoundEffectsController.defaultOneShotFadeOutSeconds, 0]
        )
        #expect(mock.fadeOutAllCalls.isEmpty)
    }

    @Test func everyCatalogStringUsesTheVoiceOverChannel() throws {
        let catalog = try StringCatalog.loadFromBundle()
        for (id, entry) in catalog.entries {
            #expect(SoundEffectsController.isVoiceOverTrack(entry.sfx), "\(id): \(entry.sfx)")
        }
    }

    @Test func enablingGameplaySuppressionStopsActiveLoops() {
        let mock = MockSoundEffectPlayer()
        let controller = SoundEffectsController(player: mock)
        controller.startLoop(trackID: "sfx_combat_loop")
        #expect(mock.loopTrackIDs == ["sfx_combat_loop"])
        controller.setGameplaySFXSuppressed(true)
        #expect(mock.loopTrackIDs.isEmpty)
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
