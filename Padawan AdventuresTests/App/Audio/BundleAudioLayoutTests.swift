import Foundation
import Testing
@testable import Padawan_Adventures

@MainActor
struct BundleAudioLayoutTests {
    @Test func noAudioAtBundleRoot() {
        let problems = ConfigAudit.checkAudioLayout()
        #expect(!problems.contains { $0.contains("must not sit at the bundle root") })
    }

    @Test func bothAudioDirectoriesPopulated() {
        let problems = ConfigAudit.checkAudioLayout()
        #expect(!problems.contains { $0.contains("Audio/FX") && $0.contains("missing or empty") })
        #expect(!problems.contains { $0.contains("Audio/Music") && $0.contains("missing or empty") })
    }

    @Test func noDuplicateAudioBasenames() {
        let problems = ConfigAudit.checkAudioLayout()
        #expect(!problems.contains { $0.contains("appears in multiple directories") })
    }

    @Test func pitMusicResolvesToMusicTrack() {
        let url = BundleMusicAudioPlayer.audioURL(
            for: "pit",
            subdirectories: ["Audio/Music"]
        )
        #expect(url != nil)
        #expect(url?.pathExtension == "mp3")
        #expect(url?.path.contains("/Audio/Music/") == true)
    }

    @Test func everyConfiguredTrackResolvesInItsOwnDirectory() throws {
        let screens = try ScreensConfig.loadFromBundle()
        for (_, screen) in screens.screens {
            assertMusicCue(screen.musicCue)
        }

        let audio = try SoundSettings.loadFromBundle()
        for (_, trackID) in audio.fx.events {
            assertFX(trackID)
        }

        let player = try PlayerConfig.loadFromBundle()
        for (_, trackID) in player.fx.events {
            assertFX(trackID)
        }

        let words = try WordCatalog.loadFromBundle()
        let letters = try LetterCatalog.loadFromBundle()
        for letter in letters.letters {
            assertFX(letter.name)
            assertFX(letter.pronunciation)
        }

        let descriptors = LevelCatalog.loadFromBundle()
        let levels = try descriptors.map { descriptor in
            try LevelConfig.loadFromBundle(
                named: descriptor.resourceName,
                subdirectory: LevelCatalog.subdirectory,
                wordCatalog: words,
                letterCatalog: letters
            )
        }
        for level in levels {
            assertMusicCue(level.musicCue)
            assertMusicCue(level.gameMusic.combatCue)
            assertMusicCue(level.gameMusic.pitCue)
            assertMusicCue(level.gameMusic.gateCue)
            for (_, trackID) in level.pit.fx.events {
                assertFX(trackID)
            }
            for (_, trackID) in level.gate.fx.events {
                assertFX(trackID)
            }
            for minigame in level.gate.minigames {
                switch minigame {
                case .spelling(let config):
                    for (_, trackID) in config.fx.events {
                        assertFX(trackID)
                    }
                    if let music = config.music {
                        assertMusicCue(MusicCue.parse(music))
                    }
                case .letterMatch(let config):
                    for (_, trackID) in config.fx.events {
                        assertFX(trackID)
                    }
                    if let music = config.music {
                        assertMusicCue(MusicCue.parse(music))
                    }
                case .wordPlug(let config):
                    for (_, trackID) in config.fx.events {
                        assertFX(trackID)
                    }
                    if let music = config.music {
                        assertMusicCue(MusicCue.parse(music))
                    }
                }
            }
        }
    }

    private func assertMusicCue(_ cue: MusicCue) {
        switch cue {
        case .unchanged, .silence:
            return
        case .track(let basename):
            let url = BundleMusicAudioPlayer.audioURL(
                for: basename,
                subdirectories: ["Audio/Music"]
            )
            #expect(url != nil, "missing music '\(basename)'")
            #expect(url?.path.contains("/Audio/Music/") == true, "music '\(basename)' not under Audio/Music")
        }
    }

    @Test func phoneticAndUIClipsResolveInSubfolders() {
        let phonetic = BundleMusicAudioPlayer.audioURL(
            for: "sfx_letter_a_name",
            subdirectories: AudioBundleLayout.fxSubdirectories
        )
        #expect(phonetic != nil)
        #expect(phonetic?.path.contains("/Audio/FX/Phonetics/") == true)

        let ui = BundleMusicAudioPlayer.audioURL(
            for: "level-screen-artifact-appear",
            subdirectories: AudioBundleLayout.fxSubdirectories
        )
        #expect(ui != nil)
        #expect(ui?.path.contains("/Audio/FX/UI/") == true)
    }

    @Test func noStaleNonPhoneticSfxBasenames() throws {
        var basenames: [String] = []
        let audio = try SoundSettings.loadFromBundle()
        basenames.append(contentsOf: audio.fx.events.values)
        let player = try PlayerConfig.loadFromBundle()
        basenames.append(contentsOf: player.fx.events.values)
        let enemies = try EnemyConfig.loadFromBundle()
        for enemy in enemies.enemies.values {
            basenames.append(contentsOf: enemy.fx.events.values)
        }
        let words = try WordCatalog.loadFromBundle()
        let letters = try LetterCatalog.loadFromBundle()
        let descriptors = LevelCatalog.loadFromBundle()
        for descriptor in descriptors {
            let level = try LevelConfig.loadFromBundle(
                named: descriptor.resourceName,
                subdirectory: LevelCatalog.subdirectory,
                wordCatalog: words,
                letterCatalog: letters
            )
            basenames.append(contentsOf: level.pit.fx.events.values)
            basenames.append(contentsOf: level.gate.fx.events.values)
            for minigame in level.gate.minigames {
                switch minigame {
                case .spelling(let config):
                    basenames.append(contentsOf: config.fx.events.values)
                case .letterMatch(let config):
                    basenames.append(contentsOf: config.fx.events.values)
                case .wordPlug(let config):
                    basenames.append(contentsOf: config.fx.events.values)
                }
            }
        }
        for basename in Set(basenames) {
            guard basename.hasPrefix("sfx_") else { continue }
            #expect(
                basename.hasPrefix("sfx_letter_") || basename.hasPrefix("sfx_word_"),
                "stale non-phonetic sfx basename '\(basename)'"
            )
        }
    }

    private func assertFX(_ basename: String) {
        let trimmed = basename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let url = BundleMusicAudioPlayer.audioURL(
            for: trimmed,
            subdirectories: AudioBundleLayout.fxSubdirectories
        )
        #expect(url != nil, "missing fx '\(trimmed)'")
        #expect(url?.path.contains("/Audio/FX/") == true, "fx '\(trimmed)' not under Audio/FX")
    }
}
