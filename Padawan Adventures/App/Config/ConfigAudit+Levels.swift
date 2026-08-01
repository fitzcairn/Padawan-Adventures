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
            return ["\(label).floor.decor_prob: \(level.floor.decorProb) out of 0...1"]
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
                return "\(label).enemies.types: unknown enemy id '\(typeID)'"
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

    static func checkWordIDs(
        level: LevelConfig,
        words: WordCatalog,
        label: String
    ) -> [String] {
        var problems: [String] = []
        for (idx, minigame) in level.pit.minigames.enumerated() {
            if case .spelling(let c) = minigame, let ids = c.wordIDs {
                for id in ids where words.word(named: id) == nil {
                    problems.append("\(label).pit.minigames[\(idx)].words: unknown word id '\(id)'")
                }
            }
        }
        for (idx, minigame) in level.gate.minigames.enumerated() {
            let ids: [String]?
            switch minigame {
            case .spelling(let c): ids = c.wordIDs
            case .wordPlug(let c): ids = c.wordIDs
            case .letterMatch: ids = nil
            }
            for id in ids ?? [] where words.word(named: id) == nil {
                problems.append("\(label).gate.minigames[\(idx)].words: unknown word id '\(id)'")
            }
        }
        return problems
    }

    static func checkLetterIDs(
        level: LevelConfig,
        letters: LetterCatalog,
        label: String
    ) -> [String] {
        var problems: [String] = []
        for (idx, minigame) in level.gate.minigames.enumerated() {
            if case .letterMatch(let c) = minigame, let ids = c.letterIDs {
                for id in ids {
                    if letters.letter(named: id) == nil {
                        problems.append(
                            "\(label).gate.minigames[\(idx)].letters: unknown letter id '\(id)'"
                        )
                    }
                }
            }
        }
        for (idx, minigame) in level.combat.minigames.enumerated() {
            if case .deflect(let c) = minigame, let ids = c.letterIDs {
                for id in ids where letters.letter(named: id) == nil {
                    problems.append(
                        "\(label).combat.minigames[\(idx)].letters: unknown letter id '\(id)'"
                    )
                }
            }
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
