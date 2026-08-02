import Foundation
import UIKit

nonisolated enum ConfigAuditError: Error, Equatable, CustomStringConvertible {
    case detail(String)

    var description: String {
        switch self {
        case .detail(let message):
            return message
        }
    }
}

/// Cross-file checks no single decoder can see (ids, audio basenames, sprites, symbols).
nonisolated enum ConfigAudit {
    static let audioExtensions = ["m4a", "caf", "wav", "mp3"]
    static let imageExtensions = ["png", "jpg", "jpeg"]

    /// Cross-file checks no single decoder can see. Throws `ConfigAuditError` with details.
    @MainActor
    static func run(
        app: AppConfig,
        levels: [LevelConfig],
        enemies: EnemyConfig,
        items: ItemsConfig,
        words: WordCatalog,
        letters: LetterCatalog,
        audio: SoundSettings,
        screens: ScreensConfig?,
        player: PlayerConfig? = nil,
        bundle: Bundle = .main
    ) throws {
        _ = app

        var problems: [String] = []

        for (index, level) in levels.enumerated() {
            let label = "levels[\(index)] (\(level.name))"
            problems.append(contentsOf: checkFloorSet(level: level, label: label, bundle: bundle))
            problems.append(contentsOf: checkLetterSet(level: level, label: label, bundle: bundle))
            problems.append(contentsOf: checkPitSet(level: level, label: label, bundle: bundle))
            problems.append(contentsOf: checkGateSet(level: level, label: label, bundle: bundle))
            problems.append(contentsOf: checkEnemyTypes(level: level, enemies: enemies, label: label))
            problems.append(contentsOf: checkWordIDs(level: level, words: words, label: label))
            problems.append(contentsOf: checkLetterIDs(level: level, letters: letters, label: label))
            problems.append(contentsOf: checkArtifact(level.artifact, label: label))
            problems.append(contentsOf: checkTreasureID(level: level, items: items, label: label, bundle: bundle))
            problems.append(contentsOf: checkLevelSprite(level.sprite, label: label, bundle: bundle))
            problems.append(contentsOf: checkMusicCue(level.musicCue, kind: "music", label: label, bundle: bundle))
            problems.append(contentsOf: checkMusicCue(
                level.gameMusic.combatCue, kind: "game_music.combat", label: label, bundle: bundle
            ))
            problems.append(contentsOf: checkMusicCue(
                level.gameMusic.pitCue, kind: "game_music.pit", label: label, bundle: bundle
            ))
            problems.append(contentsOf: checkMusicCue(
                level.gameMusic.gateCue, kind: "game_music.gate", label: label, bundle: bundle
            ))
            problems.append(contentsOf: checkFXTable(
                level.pit.fx, kind: "pit.fx", label: label, bundle: bundle
            ))
            problems.append(contentsOf: checkFXTable(
                level.gate.fx, kind: "gate.fx", label: label, bundle: bundle
            ))
            for (idx, minigame) in level.gate.minigames.enumerated() {
                switch minigame {
                case .spelling(let c):
                    problems.append(contentsOf: checkFXTable(
                        c.fx, kind: "gate.minigames[\(idx)].fx", label: label, bundle: bundle
                    ))
                    if let music = c.music {
                        problems.append(contentsOf: checkMusicCue(
                            MusicCue.parse(music),
                            kind: "gate.minigames[\(idx)].music",
                            label: label,
                            bundle: bundle
                        ))
                    }
                case .letterMatch(let c):
                    problems.append(contentsOf: checkFXTable(
                        c.fx, kind: "gate.minigames[\(idx)].fx", label: label, bundle: bundle
                    ))
                    if let music = c.music {
                        problems.append(contentsOf: checkMusicCue(
                            MusicCue.parse(music),
                            kind: "gate.minigames[\(idx)].music",
                            label: label,
                            bundle: bundle
                        ))
                    }
                case .wordPlug(let c):
                    problems.append(contentsOf: checkFXTable(
                        c.fx, kind: "gate.minigames[\(idx)].fx", label: label, bundle: bundle
                    ))
                    if let music = c.music {
                        problems.append(contentsOf: checkMusicCue(
                            MusicCue.parse(music),
                            kind: "gate.minigames[\(idx)].music",
                            label: label,
                            bundle: bundle
                        ))
                    }
                }
            }
        }

        problems.append(contentsOf: checkFXTable(audio.fx, kind: "audio.fx", label: "audio", bundle: bundle))

        if let player {
            problems.append(contentsOf: checkFXTable(
                player.fx, kind: "player.fx", label: "player", bundle: bundle
            ))
            if let sprite = player.sprite {
                problems.append(contentsOf: checkSpriteConfig(
                    sprite, label: "player.sprite", bundle: bundle
                ))
            }
            if let combatSprite = player.combatSprite {
                problems.append(contentsOf: checkSpriteConfig(
                    combatSprite, label: "player.combat_sprite", bundle: bundle
                ))
            }
        }

        for (enemyID, enemy) in enemies.enemies.sorted(by: { $0.key < $1.key }) {
            problems.append(contentsOf: checkFXTable(
                enemy.fx, kind: "fx", label: "enemies.\(enemyID)", bundle: bundle
            ))
            for (letter, shot) in enemy.shotTypes.sorted(by: { $0.key < $1.key }) {
                problems.append(contentsOf: checkFXTable(
                    shot.fx,
                    kind: "shot_types.\(letter).fx",
                    label: "enemies.\(enemyID)",
                    bundle: bundle
                ))
            }
        }

        for word in words.words {
            problems.append(contentsOf: requireFX(
                word.sfx, kind: "words.\(word.word).sfx", bundle: bundle
            ))
            if let image = word.image?.trimmingCharacters(in: .whitespacesAndNewlines),
               !image.isEmpty {
                problems.append(contentsOf: requireWordImage(
                    image, kind: "words.\(word.word).image", bundle: bundle
                ))
            }
            for (prefix, track) in word.progressive.sorted(by: { $0.key < $1.key }) {
                problems.append(contentsOf: requireFX(
                    track, kind: "words.\(word.word).progressive.\(prefix)", bundle: bundle
                ))
            }
        }

        for letter in letters.letters {
            problems.append(contentsOf: requireFX(
                letter.pronunciation, kind: "letters.\(letter.letter).pronunciation", bundle: bundle
            ))
            problems.append(contentsOf: requireFX(
                letter.name, kind: "letters.\(letter.letter).name", bundle: bundle
            ))
        }

        if let screens {
            for (screenID, screen) in screens.screens.sorted(by: { $0.key < $1.key }) {
                problems.append(contentsOf: checkMusicCue(
                    screen.musicCue,
                    kind: "music",
                    label: "screens.\(screenID)",
                    bundle: bundle
                ))
            }
        }

        problems.append(contentsOf: checkAudioLayout(bundle: bundle))
        problems.append(contentsOf: checkLevelLayout(bundle: bundle))

        if !problems.isEmpty {
            throw ConfigAuditError.detail(problems.joined(separator: "; "))
        }
    }
}
