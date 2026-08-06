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
        letters: GraphemeCatalog,
        audio: SoundSettings,
        screens: ScreensConfig?,
        player: PlayerConfig? = nil,
        vocabularyCatalog: LevelVocabularyCatalog? = nil,
        bundle: Bundle = .main
    ) throws {
        _ = app

        var problems: [String] = []

        let vocabCatalog: LevelVocabularyCatalog
        if let vocabularyCatalog {
            vocabCatalog = vocabularyCatalog
        } else {
            do {
                vocabCatalog = try LevelVocabularyCatalog.loadFromBundle()
            } catch {
                vocabCatalog = .fallback
            }
        }
        problems.append(contentsOf: checkDuplicateVocabularyIDs(vocabularyCatalog: vocabCatalog))

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
        }

        // Every music/fx basename config can reach, gathered once so the orphan check in
        // `checkOrphanAudio` cannot drift from what is validated here.
        for reference in audioReferences(
            levels: levels,
            enemies: enemies,
            words: words,
            letters: letters,
            audio: audio,
            screens: screens,
            player: player
        ) {
            switch reference.tree {
            case .music:
                problems.append(contentsOf: requireMusic(
                    reference.basename, kind: reference.kind, bundle: bundle
                ))
            case .fx:
                problems.append(contentsOf: requireFX(
                    reference.basename, kind: reference.kind, bundle: bundle
                ))
            }
        }

        if let player {
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

        for word in words.words {
            guard let image = word.image?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !image.isEmpty else {
                continue
            }
            problems.append(contentsOf: requireWordImage(
                image, kind: "words.\(word.word).image", bundle: bundle
            ))
        }

        problems.append(contentsOf: checkAudioLayout(bundle: bundle))
        problems.append(contentsOf: checkLevelLayout(bundle: bundle))

        if !problems.isEmpty {
            throw ConfigAuditError.detail(problems.joined(separator: "; "))
        }
    }
}
