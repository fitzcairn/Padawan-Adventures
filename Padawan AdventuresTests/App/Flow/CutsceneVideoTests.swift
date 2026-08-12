import AVFoundation
import Testing
@testable import Padawan_Adventures

/// The movie carries the game's only spoken story, so it rides the sound-effects
/// channel. Reading the music channel instead used to mean a muted score muted the
/// story, and the boost that lifted dialogue off the quiet music bed clamped at the
/// top of the slider.
@MainActor
struct CutsceneVideoTests {
    private func makeVideo(enabled: Bool = true, volume: Float = 1) async -> CutsceneVideo {
        let effects = SoundEffectsController(player: MockSoundEffectPlayer())
        effects.setSoundEffectsEnabled(enabled)
        effects.setSoundEffectsVolume(volume)
        let video = CutsceneVideo(effects: effects)
        await video.preload()
        return video
    }

    /// Level comes from the effects channel alone, so the music setting cannot reach it.
    @Test func volumeFollowsTheEffectsChannel() async {
        let video = await makeVideo()
        #expect(video.player?.volume == SoundEffectsController.cutsceneVolumeScale)
    }

    @Test func mutingEffectsSilencesTheMovie() async {
        let video = await makeVideo(enabled: false)
        #expect(video.player?.volume == 0)
    }

    /// Halving the slider halves the movie all the way to the top of its range; a
    /// boosted level would have clamped there and flattened against the rest of the mix.
    @Test func volumeStaysLinearAcrossTheSlider() async {
        let full = await makeVideo(volume: 1)
        let half = await makeVideo(volume: 0.5)
        #expect(full.player?.volume == SoundEffectsController.cutsceneVolumeScale)
        #expect(half.player?.volume == SoundEffectsController.cutsceneVolumeScale / 2)
        #expect((full.player?.volume ?? 1) < 1)
    }

    /// The story sits above ambience and below the letter cues that must cut through play.
    @Test func cutsceneSitsBetweenAmbienceAndPhoneticCues() {
        #expect(SoundEffectsController.cutsceneVolumeScale
            > SoundEffectsController.backgroundSFXVolumeScale)
        #expect(SoundEffectsController.cutsceneVolumeScale
            < min(1, SoundEffectsController.phoneticVolumeScale))
    }
}
