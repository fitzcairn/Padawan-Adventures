import Foundation

/// User-tunable music and sound-effect preferences, persisted in `UserDefaults`.
@MainActor
@Observable
final class AudioPreferences {
    static let shared = AudioPreferences()

    private enum Keys {
        static let soundEffectsEnabled = "audio.soundEffectsEnabled"
        static let soundEffectsVolume = "audio.soundEffectsVolume"
        static let musicEnabled = "audio.musicEnabled"
        static let musicVolume = "audio.musicVolume"
    }

    private let defaults: UserDefaults
    private var isLoading: Bool

    var soundEffectsEnabled: Bool {
        didSet {
            guard !isLoading, soundEffectsEnabled != oldValue else { return }
            defaults.set(soundEffectsEnabled, forKey: Keys.soundEffectsEnabled)
            applySoundEffects()
        }
    }

    var soundEffectsVolume: Float {
        didSet {
            guard !isLoading else { return }
            let clamped = Self.clamp(soundEffectsVolume)
            if clamped != soundEffectsVolume {
                soundEffectsVolume = clamped
                return
            }
            guard soundEffectsVolume != oldValue else { return }
            defaults.set(Double(soundEffectsVolume), forKey: Keys.soundEffectsVolume)
            applySoundEffects()
        }
    }

    var musicEnabled: Bool {
        didSet {
            guard !isLoading, musicEnabled != oldValue else { return }
            defaults.set(musicEnabled, forKey: Keys.musicEnabled)
            applyMusic()
        }
    }

    var musicVolume: Float {
        didSet {
            guard !isLoading else { return }
            let clamped = Self.clamp(musicVolume)
            if clamped != musicVolume {
                musicVolume = clamped
                return
            }
            guard musicVolume != oldValue else { return }
            defaults.set(Double(musicVolume), forKey: Keys.musicVolume)
            applyMusic()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isLoading = true

        if defaults.object(forKey: Keys.soundEffectsEnabled) == nil {
            soundEffectsEnabled = true
        } else {
            soundEffectsEnabled = defaults.bool(forKey: Keys.soundEffectsEnabled)
        }

        if defaults.object(forKey: Keys.soundEffectsVolume) == nil {
            soundEffectsVolume = 1
        } else {
            soundEffectsVolume = Self.clamp(Float(defaults.double(forKey: Keys.soundEffectsVolume)))
        }

        if defaults.object(forKey: Keys.musicEnabled) == nil {
            musicEnabled = true
        } else {
            musicEnabled = defaults.bool(forKey: Keys.musicEnabled)
        }

        if defaults.object(forKey: Keys.musicVolume) == nil {
            musicVolume = 1
        } else {
            musicVolume = Self.clamp(Float(defaults.double(forKey: Keys.musicVolume)))
        }

        isLoading = false
    }

    /// Current values as a per-player settings snapshot.
    var snapshot: PlayerSettings {
        PlayerSettings(
            soundEffectsEnabled: soundEffectsEnabled,
            soundEffectsVolume: soundEffectsVolume,
            musicEnabled: musicEnabled,
            musicVolume: musicVolume
        )
    }

    /// Replaces preferences from per-player settings and pushes them to controllers.
    func apply(_ settings: PlayerSettings) {
        isLoading = true
        soundEffectsEnabled = settings.soundEffectsEnabled
        soundEffectsVolume = settings.soundEffectsVolume
        musicEnabled = settings.musicEnabled
        musicVolume = settings.musicVolume
        defaults.set(soundEffectsEnabled, forKey: Keys.soundEffectsEnabled)
        defaults.set(Double(soundEffectsVolume), forKey: Keys.soundEffectsVolume)
        defaults.set(musicEnabled, forKey: Keys.musicEnabled)
        defaults.set(Double(musicVolume), forKey: Keys.musicVolume)
        isLoading = false
        applyToControllers()
    }

    /// Pushes current values into the shared audio controllers without re-writing defaults.
    func applyToControllers() {
        applySoundEffects()
        applyMusic()
    }

    private func applySoundEffects() {
        SoundEffectsController.shared.setSoundEffectsEnabled(soundEffectsEnabled)
        SoundEffectsController.shared.setSoundEffectsVolume(soundEffectsVolume)
    }

    private func applyMusic() {
        BackgroundMusicController.shared.setMusicEnabled(musicEnabled)
        BackgroundMusicController.shared.setMusicVolume(musicVolume)
    }

    private static func clamp(_ value: Float) -> Float {
        min(1, max(0, value))
    }
}
