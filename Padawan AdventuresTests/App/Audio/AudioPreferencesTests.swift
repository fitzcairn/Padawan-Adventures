import Foundation
import Testing
@testable import Padawan_Adventures

@MainActor
struct AudioPreferencesTests {
    @Test func defaultsWhenKeysMissing() {
        let defaults = Self.makeSuite()
        let prefs = AudioPreferences(defaults: defaults)
        #expect(prefs.soundEffectsEnabled)
        #expect(prefs.soundEffectsVolume == 1)
        #expect(prefs.musicEnabled)
        #expect(prefs.musicVolume == 1)
    }

    @Test func clampsVolumeToUnitInterval() {
        let defaults = Self.makeSuite()
        let prefs = AudioPreferences(defaults: defaults)
        prefs.soundEffectsVolume = 1.5
        prefs.musicVolume = -0.2
        #expect(prefs.soundEffectsVolume == 1)
        #expect(prefs.musicVolume == 0)
    }

    @Test func persistsAndReloads() {
        let suiteName = "AudioPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let prefs = AudioPreferences(defaults: defaults)
        prefs.soundEffectsEnabled = false
        prefs.soundEffectsVolume = 0.25
        prefs.musicEnabled = false
        prefs.musicVolume = 0.75

        let reloaded = AudioPreferences(defaults: defaults)
        #expect(!reloaded.soundEffectsEnabled)
        #expect(reloaded.soundEffectsVolume == 0.25)
        #expect(!reloaded.musicEnabled)
        #expect(reloaded.musicVolume == 0.75)
    }

    private static func makeSuite() -> UserDefaults {
        let suiteName = "AudioPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
