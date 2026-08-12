import Foundation

/// Process-lifetime owner of overlapping one-shot sound effects.
@MainActor
final class SoundEffectsController {
    static let shared = SoundEffectsController()

    /// Phonetic letter/word cues play at this multiple of `soundEffectsVolume`
    /// (clamped to 1) so they sit above music and background FX.
    static let phoneticVolumeScale: Float = 1.2
    /// Non-phonetic ambience/action SFX (hum, slash, arc, jump, …). Half of the
    /// unboosted SFX level, then ducked by `phoneticVolumeScale` so letter cues
    /// stay ~20% clearer even when phonetic playback is clamped at 1.
    static let backgroundSFXVolumeScale: Float = 0.5 / phoneticVolumeScale
    /// Cutscene movie dialogue. The half-level that ambience sits at before its phonetic
    /// duck, which the movie skips because no letter cues play over it. Every
    /// asset is normalised to the same loudness, so this lands the story a comfortable
    /// step above ambience and below the letter cues. Keeping it under 1 also leaves the
    /// volume slider linear to the top, where a boosted level would clamp instead.
    static let cutsceneVolumeScale: Float = 0.5

    /// While a phonetic cue plays, music and ambience loops drop to this fraction
    /// of their normal mix level so letter/word audio stays clear in every minigame.
    static let phoneticCueDuckScale: Float = 0.35
    /// Extra phonetic-vs-FX separation while combat mix is active (+30% relative).
    static let combatPhoneticRelativeBoost: Float = 1.3
    /// Extra attenuation for lightsaber hum / slash / ignite / cut clips.
    static let lightsaberSFXVolumeScale: Float = 0.45

    /// Voice-over lines from `strings.yaml` share one channel, so starting a line
    /// crossfades the one already playing out over this window. Short enough that the
    /// new line's first syllable is still crisp.
    nonisolated static let voiceOverCrossfadeSeconds: TimeInterval = 0.2

    private(set) var soundEffectsEnabled = true
    private(set) var soundEffectsVolume: Float = 1
    /// When true, phonetics get `combatPhoneticRelativeBoost` and other FX are ducked by the same factor.
    private(set) var isCombatMixActive = false
    /// When true, gameplay one-shots and loops are ignored so tutorial voice-over
    /// (`sfx_ui_*`) can play alone during the demo lead-in.
    private(set) var isGameplaySFXSuppressed = false
    /// Shared FX from `sound.yaml` (`win`, `lose`, `error`, `correct`, …).
    private(set) var commonFx: SoundEffectTable = SoundSettings.fallback.fx

    private let player: any SoundEffectPlaying
    /// Optional seam so unit tests can observe cue-ducking without touching BGM.
    var phoneticCueDuckHandler: ((TimeInterval) -> Void)?
    private var phoneticLoopDuckTask: Task<Void, Never>?
    private var phoneticLoopDuckGeneration = 0

    init(player: (any SoundEffectPlaying)? = nil) {
        self.player = player ?? BundleSoundEffectPlayer()
    }

    func setSoundEffectsEnabled(_ enabled: Bool) {
        soundEffectsEnabled = enabled
        if !enabled {
            stopAllLoops()
        }
    }

    func setSoundEffectsVolume(_ volume: Float) {
        soundEffectsVolume = min(1, max(0, volume))
    }

    /// Combat-only mix: letter cues sit another 30% above slash/hum/other FX.
    func setCombatMixActive(_ active: Bool) {
        isCombatMixActive = active
    }

    /// Suppresses minigame begin / ambience SFX while keeping tutorial VO (`sfx_ui_*`).
    /// Enabling also stops any active loops so a hum started in `buildContent` cannot
    /// bleed under the voice-over.
    func setGameplaySFXSuppressed(_ suppressed: Bool) {
        isGameplaySFXSuppressed = suppressed
        if suppressed {
            stopAllLoops()
        }
    }

    func configure(commonFx: SoundEffectTable) {
        self.commonFx = commonFx
    }

    /// Warms the clip pool for the given track ids without starting playback.
    func prepare(trackIDs: [String]) {
        player.prepare(trackIDs: trackIDs)
    }

    /// Plays a track by basename under `Resources/Audio/FX/`. Missing assets are ignored.
    /// Phonetic cues duck music + ambience loops for the clip duration (all minigames).
    /// UI voice-over (`sfx_ui_*`) is exclusive: a new line crossfades out the previous one.
    func play(trackID: String) {
        guard soundEffectsEnabled else { return }
        let trimmed = trackID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if isGameplaySFXSuppressed, !Self.isVoiceOverTrack(trimmed) { return }
        let volume = playbackVolume(for: trimmed)
        let didPlay: Bool
        if Self.isVoiceOverTrack(trimmed) {
            didPlay = player.playVoiceOver(
                trackID: trimmed,
                volume: volume,
                crossfade: Self.voiceOverCrossfadeSeconds
            )
        } else {
            didPlay = player.play(trackID: trimmed, volume: volume)
        }
        if didPlay, Self.isPhoneticTrack(trimmed) {
            duckAmbienceForPhoneticCue(duration: cueDuration(of: trimmed))
        }
    }

    /// Looks up `event` in `table` and plays it. Unmapped events and missing assets are ignored.
    func play(event: String, from table: SoundEffectTable) {
        guard let trackID = table.trackID(for: event) else { return }
        play(trackID: trackID)
    }

    /// Plays a shared event from `sound.yaml` (`win`, `lose`, `error`, `correct`, …).
    /// When `override` is a non-empty track basename, that track is used instead.
    func playCommon(event: String, override: String? = nil) {
        if let override = override?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            play(trackID: override)
            return
        }
        play(event: event, from: commonFx)
    }

    /// Starts an indefinitely looping ambience track (lightsaber hum, gate arc).
    /// `volumeScale` multiplies the normal playback level (`1` = full mix level).
    func startLoop(trackID: String, volumeScale: Float = 1) {
        guard soundEffectsEnabled else { return }
        let trimmed = trackID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if isGameplaySFXSuppressed, !Self.isVoiceOverTrack(trimmed) { return }
        let scale = min(1, max(0, volumeScale))
        player.startLoop(trackID: trimmed, volume: playbackVolume(for: trimmed) * scale)
    }

    /// Looks up `event` in `table` and starts it as a loop. Returns the track id so
    /// the caller can stop the exact track it started. Returns `nil` when suppressed
    /// or disabled so callers do not track a loop that never began.
    @discardableResult
    func startLoop(
        event: String,
        from table: SoundEffectTable,
        volumeScale: Float = 1
    ) -> String? {
        guard let trackID = table.trackID(for: event) else { return nil }
        guard soundEffectsEnabled else { return nil }
        if isGameplaySFXSuppressed, !Self.isVoiceOverTrack(trackID) { return nil }
        startLoop(trackID: trackID, volumeScale: volumeScale)
        return trackID
    }

    func stopLoop(trackID: String?) {
        guard let trimmed = trackID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return }
        player.stopLoop(trackID: trimmed)
    }

    func stopAllLoops() {
        player.stopAllLoops()
    }

    /// Default fade when silencing FX that should yield to minigame / combat audio.
    /// `nonisolated` so it can be used as a default argument below, which is
    /// evaluated outside the main actor.
    nonisolated static let defaultOneShotFadeOutSeconds: TimeInterval = 0.35

    /// Fades a playing one-shot to silence and stops it (no-op if not playing).
    func fadeOutAndStop(
        trackID: String?,
        duration: TimeInterval = defaultOneShotFadeOutSeconds
    ) {
        guard let trimmed = trackID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return }
        player.fadeOutAndStop(trackID: trimmed, duration: max(0, duration))
    }

    /// Fades every currently playing FX one-shot and loop to silence, then stops them.
    func fadeOutAndStopAll(duration: TimeInterval = defaultOneShotFadeOutSeconds) {
        player.fadeOutAndStopAll(duration: max(0, duration))
    }

    /// Fades out the voice-over line currently on the exclusive channel, leaving
    /// gameplay FX and music alone. Used when a tutorial finishes so its narration
    /// does not outlive the screen that started it.
    func fadeOutVoiceOver(duration: TimeInterval = defaultOneShotFadeOutSeconds) {
        player.fadeOutVoiceOver(duration: max(0, duration))
    }

    /// Clip length, or nil for a blank or unresolvable track.
    func duration(of trackID: String?) -> TimeInterval? {
        guard let trimmed = trackID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return player.duration(of: trimmed)
    }

    /// Clip length for timing a follow-up action, with the puzzle scenes' historic
    /// 0.7s fallback and 0.35s floor.
    func cueDuration(of trackID: String?) -> TimeInterval {
        max(duration(of: trackID) ?? 0.7, 0.35)
    }

    /// Phonetics are boosted; non-phonetic FX are ducked relative to that boost.
    private func playbackVolume(for trackID: String) -> Float {
        if Self.isPhoneticTrack(trackID) {
            var scale = Self.phoneticVolumeScale
            if isCombatMixActive {
                scale *= Self.combatPhoneticRelativeBoost
            }
            return min(1, soundEffectsVolume * scale)
        }
        var scale = Self.backgroundSFXVolumeScale
        if isCombatMixActive {
            scale /= Self.combatPhoneticRelativeBoost
        }
        if Self.isLightsaberTrack(trackID) {
            scale *= Self.lightsaberSFXVolumeScale
        }
        return soundEffectsVolume * scale
    }

    /// Phonetic / voice clips use `sfx_letter_*` (under `Audio/FX/Letters/`),
    /// `sfx_grapheme_*` (under `Audio/FX/Graphemes/`), `sfx_word_*`
    /// (under `Audio/FX/Words/`), and `sfx_ui_*` (under `Audio/FX/UI/`) basenames.
    static func isPhoneticTrack(_ trackID: String) -> Bool {
        trackID.hasPrefix("sfx_letter_")
            || trackID.hasPrefix("sfx_grapheme_")
            || trackID.hasPrefix("sfx_word_")
            || trackID.hasPrefix("sfx_ui_")
    }

    /// UI voice-over clips under `Audio/FX/UI/` — every `sfx` in `strings.yaml`. These
    /// share one exclusive channel and are allowed while gameplay SFX are suppressed
    /// during the tutorial demo lead-in.
    static func isVoiceOverTrack(_ trackID: String) -> Bool {
        trackID.hasPrefix("sfx_ui_")
    }

    /// Combat saber one-shots and the looping hum (`*lightsaber*` basenames).
    static func isLightsaberTrack(_ trackID: String) -> Bool {
        trackID.localizedCaseInsensitiveContains("lightsaber")
    }

    /// Ducks music + ambience loops for `duration` on behalf of audio that has no
    /// track id (TTS phrases). Overlapping calls extend the window.
    func duckAmbience(for duration: TimeInterval) {
        duckAmbienceForPhoneticCue(duration: duration)
    }

    private func duckAmbienceForPhoneticCue(duration: TimeInterval) {
        let hold = max(duration, 0.05)
        if let phoneticCueDuckHandler {
            phoneticCueDuckHandler(hold)
        } else {
            BackgroundMusicController.shared.duckForPhoneticCue(duration: hold)
        }

        phoneticLoopDuckGeneration += 1
        let generation = phoneticLoopDuckGeneration
        phoneticLoopDuckTask?.cancel()
        player.setLoopDuckScale(Self.phoneticCueDuckScale)
        phoneticLoopDuckTask = Task { @MainActor in
            let nanos = UInt64(hold * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled, generation == self.phoneticLoopDuckGeneration else { return }
            self.player.setLoopDuckScale(1)
            self.phoneticLoopDuckTask = nil
        }
    }
}
