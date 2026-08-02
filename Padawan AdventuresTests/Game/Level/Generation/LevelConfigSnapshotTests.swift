import Testing
@testable import Padawan_Adventures

/// Decode snapshots for every shipped level. Guards Phase 3c / Phase 4 registry work.
struct LevelConfigSnapshotTests {
    @Test func everyShippedLevelDecodesWithDerivedArt() throws {
        let catalog = LevelCatalog.loadFromBundle()
        #expect(!catalog.isEmpty, "expected shipped levels in the bundle")

        for descriptor in catalog {
            let level = try LevelConfig.loadFromBundle(
                named: descriptor.resourceName,
                subdirectory: LevelCatalog.subdirectory
            )
            #expect(level.name == descriptor.displayName)
            #expect(level.order == descriptor.order)
            #expect(level.color == descriptor.color)
            #expect(level.treasure == descriptor.treasure)
            #expect(level.artifact == descriptor.artifact)
            #expect(level.floor.set == descriptor.resourceName)
            #expect(level.letters.set == descriptor.resourceName)
            #expect(level.sprite?.root == "Levels/\(descriptor.resourceName)")
            #expect(!level.combat.minigames.isEmpty)
            #expect(!level.gate.minigames.isEmpty)
            #expect(!level.pit.minigames.isEmpty)
        }
    }

    @Test func tythonResolvedFieldsMatchSnapshot() throws {
        let level = try LevelConfig.loadFromBundle(
            named: "1-tython",
            subdirectory: LevelCatalog.subdirectory
        )

        #expect(level.name == "Tython")
        #expect(level.order == 1)
        #expect(level.color == "#2E7D32")
        #expect(level.artifact == "leaf.fill")
        #expect(level.treasure == "emitter")
        #expect(level.floor.set == "1-tython")
        #expect(level.letters.set == "1-tython")
        #expect(level.sprite?.root == "Levels/1-tython")
        #expect(level.width == 20)
        #expect(level.roomCount == 5)
        #expect(level.enemies?.types == ["dino", "treant"])
        #expect(level.combatLetterSpawnRate == 0.7)
        #expect(level.combatLetterCase == .lower)

        #expect(level.combat.minigames.map(\.kind) == [.slash, .deflect])
        #expect(level.combat.minigames.map(\.weight) == [0, 1])
        guard case .deflect(let deflect) = level.combat.minigames[1] else {
            Issue.record("expected deflect combat entry")
            return
        }
        #expect(deflect.monsterHP == 5)
        #expect(deflect.orbTravelSeconds == 3)
        #expect(deflect.letters.map(\.letter) == ["a", "b", "c", "d"])

        #expect(level.gate.minigameChance == 1.0)
        #expect(level.gate.fx.trackID(for: "opened") == "gate-open")
        #expect(level.gate.minigames.map(\.kind) == [.wordPlug])
        guard case .wordPlug(let wordPlug) = level.gate.minigames[0] else {
            Issue.record("expected word-plug gate entry")
            return
        }
        #expect(wordPlug.wordCountMin == 2)
        #expect(wordPlug.wordCountMax == 2)
        #expect(wordPlug.words.map(\.word) == [
            "bath", "book", "cat", "dance", "dog", "lightbulb", "star", "wand",
        ])

        #expect(level.pit.minigames.map(\.kind) == [.spelling, .bridge])
        #expect(level.pit.minigames.map(\.weight) == [0, 1])
        guard case .spelling(let spelling) = level.pit.minigames[0] else {
            Issue.record("expected pit spelling entry")
            return
        }
        #expect(spelling.words.map(\.word) == ["cat", "dog", "star"])
        guard case .bridge(let bridge) = level.pit.minigames[1] else {
            Issue.record("expected pit bridge entry")
            return
        }
        #expect(bridge.words == ["car", "start", "dog", "trash", "sun", "kam"])
    }
}
