import Foundation
import UIKit

extension ConfigAudit {
    static func checkFloorSet(
        level: LevelConfig,
        label: String,
        bundle: Bundle
    ) -> [String] {
        let setName = level.floor.set.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !setName.isEmpty else {
            return ["\(label).floor.set: empty"]
        }
        do {
            let tileSet = try FloorTileSet.loadFromBundle(set: setName, bundle: bundle)
            if tileSet.floorTileIDs.isEmpty {
                return ["\(label).floor.set: '\(setName)' has no role=floor tiles"]
            }
        } catch {
            return ["\(label).floor.set: missing or invalid atlas for '\(setName)' (\(error))"]
        }
        if level.floor.decorProb < 0 || level.floor.decorProb > 1 {
            return ["\(label).world.floor.decor_probability: \(level.floor.decorProb) out of 0...1"]
        }
        if level.floor.cohesion < 0 || level.floor.cohesion > 1 {
            return ["\(label).world.floor.cohesion_fraction: \(level.floor.cohesion) out of 0...1"]
        }
        return []
    }

    static func checkLetterSet(
        level: LevelConfig,
        label: String,
        bundle: Bundle
    ) -> [String] {
        let setName = level.letters.set.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !setName.isEmpty else {
            return ["\(label).letters.set: empty"]
        }
        do {
            let letterSet = try LetterSpriteSet.loadFromBundle(set: setName, bundle: bundle)
            if letterSet.frames.count != 52 {
                return [
                    "\(label).letters.set: '\(setName)' has \(letterSet.frames.count) frames, expected 52"
                ]
            }
            let missing = letterSet.missingKeys
            if !missing.isEmpty {
                return [
                    "\(label).letters.set: '\(setName)' missing glyphs \(missing.joined(separator: ","))"
                ]
            }
        } catch {
            return ["\(label).letters.set: missing or invalid atlas for '\(setName)' (\(error))"]
        }
        return []
    }

    /// Pit platforms share the floor set name (`Levels/{floor.set}/`).
    static func checkPitSet(
        level: LevelConfig,
        label: String,
        bundle: Bundle
    ) -> [String] {
        let setName = level.floor.set.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !setName.isEmpty else {
            return ["\(label).floor.set: empty (required for pit sprites)"]
        }
        do {
            let pitSet = try PitSpriteSet.loadFromBundle(set: setName, bundle: bundle)
            if pitSet.frames.isEmpty {
                return ["\(label).pit set '\(setName)': has no platform tiles"]
            }
        } catch {
            return ["\(label).pit set '\(setName)': missing or invalid atlas (\(error))"]
        }
        return []
    }

    /// World gate walls share the floor set name (`Levels/{floor.set}/`).
    static func checkGateSet(
        level: LevelConfig,
        label: String,
        bundle: Bundle
    ) -> [String] {
        let setName = level.floor.set.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !setName.isEmpty else {
            return ["\(label).floor.set: empty (required for gate sprites)"]
        }
        do {
            let gateSet = try GateSpriteSet.loadFromBundle(set: setName, bundle: bundle)
            let axes = Set(gateSet.axisIDs)
            let expected = Set(GateSpriteSet.Axis.allCases.map(\.rawValue))
            if axes != expected {
                return [
                    "\(label).gate set '\(setName)': expected frames \(expected.sorted()), got \(axes.sorted())"
                ]
            }
        } catch {
            return ["\(label).gate set '\(setName)': missing or invalid atlas (\(error))"]
        }
        return []
    }

    static func checkEnemyTypes(
        level: LevelConfig,
        enemies: EnemyConfig,
        label: String
    ) -> [String] {
        guard let spawn = level.enemies else { return [] }
        return spawn.types.compactMap { typeID in
            guard enemies.type(named: typeID) != nil else {
                return "\(label).world.enemies.types: unknown enemy id '\(typeID)'"
            }
            return nil
        }
    }

    static func checkTreasureID(
        level: LevelConfig,
        items: ItemsConfig,
        label: String,
        bundle: Bundle
    ) -> [String] {
        guard let id = level.treasure else { return [] }
        guard let sprite = items.items[id]?.sprite else {
            return ["\(label).treasure: unknown item id '\(id)' in items.yaml"]
        }
        return checkSpriteConfig(sprite, label: "\(label).treasure.sprite", bundle: bundle)
    }

    /// Every word in the level's cumulative vocabulary resolves in `words.yaml`,
    /// reconstructs from its graphemes, and those graphemes sit in the pool.
    static func checkWordIDs(
        level: LevelConfig,
        words: WordCatalog,
        label: String
    ) -> [String] {
        var problems: [String] = []
        let poolGraphemes = Set(level.vocabulary.allGraphemes.map(\.grapheme))
        for entry in level.vocabulary.allWords {
            guard let catalogEntry = words.word(named: entry.word) else {
                problems.append("\(label).vocab.words: unknown word id '\(entry.word)'")
                continue
            }
            if catalogEntry.graphemes.joined() != entry.word {
                problems.append(
                    "\(label).vocab.words: '\(entry.word)' graphemes do not reconstruct the word"
                )
            }
            for grapheme in entry.graphemes where !poolGraphemes.contains(grapheme) {
                problems.append(
                    "\(label).vocab.words: '\(entry.word)' uses grapheme '\(grapheme)' outside the cumulative pool"
                )
            }
        }
        return problems
    }

    /// Every grapheme in the level's cumulative vocabulary resolves in `graphemes.yaml`.
    static func checkLetterIDs(
        level: LevelConfig,
        letters: GraphemeCatalog,
        label: String
    ) -> [String] {
        level.vocabulary.allGraphemes.compactMap { entry in
            guard letters.grapheme(named: entry.grapheme) != nil else {
                return "\(label).vocab.graphemes: unknown letter id '\(entry.grapheme)'"
            }
            return nil
        }
    }

    /// Ids declared in more than one level's `vocab:` block (lowest order wins at runtime).
    static func checkDuplicateVocabularyIDs(
        vocabularyCatalog: LevelVocabularyCatalog
    ) -> [String] {
        var problems: [String] = []
        for id in vocabularyCatalog.duplicateWordIDs {
            problems.append("vocab.words: '\(id)' is declared at more than one level")
        }
        for id in vocabularyCatalog.duplicateGraphemeIDs {
            problems.append("vocab.graphemes: '\(id)' is declared at more than one level")
        }
        return problems
    }

    @MainActor
    static func checkArtifact(_ artifact: String, label: String) -> [String] {
        let trimmed = artifact.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ["\(label).artifact: must be non-empty"]
        }
        guard UIImage(systemName: trimmed) != nil else {
            return ["\(label).artifact: '\(trimmed)' is not a valid SF Symbol"]
        }
        return []
    }

    static func checkLevelSprite(
        _ sprite: SpriteConfig?,
        label: String,
        bundle: Bundle
    ) -> [String] {
        guard let sprite else { return [] }
        return checkSpriteConfig(sprite, label: "\(label).sprite", bundle: bundle)
    }
}
