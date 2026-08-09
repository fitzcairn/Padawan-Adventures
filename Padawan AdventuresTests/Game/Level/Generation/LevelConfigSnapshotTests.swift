import Testing
@testable import Padawan_Adventures

/// Decode snapshots for every shipped level. Guards Phase 3c / Phase 4 registry work.
struct LevelConfigSnapshotTests {
    private static let level1Words = [
        "an", "at", "in", "it", "nap", "pan", "pat", "pin", "sat", "sip", "sit", "tap",
    ]
    private static let level1Graphemes = ["s", "a", "t", "p", "i", "n"]

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
            #expect(!level.vocabulary.allWords.isEmpty)
            #expect(!level.vocabulary.allGraphemes.isEmpty)
        }
    }

    @Test func tythonResolvedFieldsMatchSnapshot() throws {
        let level = try LevelConfig.loadFromBundle(
            named: "1-tython",
            subdirectory: LevelCatalog.subdirectory
        )

        #expect(level.name == "Tython")
        #expect(level.order == 1)
        #expect(level.worldTutorial)
        #expect(level.color == "#2E7D32")
        #expect(level.artifact == "leaf.fill")
        #expect(level.treasure == "emitter")
        #expect(level.floor.set == "1-tython")
        #expect(level.letters.set == "1-tython")
        #expect(level.sprite?.root == "Levels/1-tython")
        #expect(level.width == 20)
        #expect(level.roomCount == 5)
        #expect(level.enemies?.types == ["dino", "treant"])
        #expect(level.currentLevelProbability == 0.75)
        #expect(level.vocabulary.allWords.map(\.word) == Self.level1Words)
        #expect(level.vocabulary.allGraphemes.map(\.grapheme) == ["s", "a", "t", "p", "i", "n"])
        #expect(level.vocabulary.letters == Self.level1Graphemes)

        #expect(level.combat.minigames.map(\.kind) == [
            .slash, .startingSoundDeflect, .endingSoundDeflect,
        ])
        #expect(level.combat.minigames.map(\.weight) == [1.0, 0.0, 0.0])
        guard case .slash(let slash) = level.combat.minigames[0] else {
            Issue.record("expected slash combat entry")
            return
        }
        #expect(slash.minDecoyCount == 2)
        #expect(slash.maxDecoyCount == 4)
        #expect(slash.graphemeCase == .lower)
        #expect(slash.graphemeSoundRepeatSeconds == 3)
        guard case .deflect(let deflect) = level.combat.minigames[1] else {
            Issue.record("expected starting-sound deflect combat entry")
            return
        }
        #expect(deflect.letterPosition == .starting)
        #expect(deflect.monsterHP == 5)
        #expect(deflect.orbTravelSeconds == 8)
        #expect(deflect.ringCount == 4)
        #expect(deflect.graphemes.map(\.grapheme) == ["s", "a", "t", "p"])
        guard case .deflect(let endingDeflect) = level.combat.minigames[2] else {
            Issue.record("expected ending-sound deflect combat entry")
            return
        }
        #expect(endingDeflect.letterPosition == .ending)
        #expect(endingDeflect.monsterHP == 5)
        #expect(endingDeflect.orbTravelSeconds == 8)
        #expect(endingDeflect.ringCount == 4)
        // Level 1 ending candidates are t/p/n only; ring_count clamps to 3.
        #expect(endingDeflect.graphemes.map(\.grapheme) == ["t", "p", "n"])

        #expect(level.gate.minigameChance == 1.0)
        #expect(level.gate.fx.trackID(for: "opened") == "gate-open")
        #expect(level.gate.minigames.map(\.kind) == [.wordPlug, .endingSoundPlug, .soundOutWord, .graphemeMatch])
        #expect(level.gate.minigames.map(\.weight) == [0, 0, 0, 1])
        guard case .wordPlug(let wordPlug) = level.gate.minigames[0] else {
            Issue.record("expected word-plug gate entry")
            return
        }
        #expect(wordPlug.wordCountMin == 2)
        #expect(wordPlug.wordCountMax == 2)
        #expect(wordPlug.words.map(\.word) == Self.level1Words)
        guard case .wordPlug(let endingSound) = level.gate.minigames[1] else {
            Issue.record("expected ending-sound gate entry")
            return
        }
        #expect(endingSound.letterPosition == .ending)
        #expect(endingSound.words.map(\.word) == Self.level1Words)

        #expect(level.pit.minigames.map(\.kind) == [.soundOutWord, .bridge, .startingSoundBridge])
        #expect(level.pit.minigames.map(\.weight) == [1, 0, 0])
        guard case .soundOutWord(let soundOut) = level.pit.minigames[0] else {
            Issue.record("expected pit sound-out-word entry")
            return
        }
        #expect(soundOut.words.map(\.word) == Self.level1Words)
        guard case .bridge(let bridge) = level.pit.minigames[1] else {
            Issue.record("expected pit bridge entry")
            return
        }
        #expect(bridge.letterPosition == .ending)
        #expect(bridge.words.map(\.word) == Self.level1Words)
        guard case .bridge(let starting) = level.pit.minigames[2] else {
            Issue.record("expected pit starting-sound bridge entry")
            return
        }
        #expect(starting.letterPosition == .starting)
        #expect(starting.words.map(\.word) == Self.level1Words)
    }

    @Test func onlyTythonOptsIntoWorldTutorial() throws {
        let catalog = LevelCatalog.loadFromBundle()
        #expect(!catalog.isEmpty)
        for descriptor in catalog {
            let level = try LevelConfig.loadFromBundle(
                named: descriptor.resourceName,
                subdirectory: LevelCatalog.subdirectory
            )
            if descriptor.resourceName == "1-tython" {
                #expect(level.worldTutorial, "1-tython should enable world_tutorial")
            } else {
                #expect(!level.worldTutorial, "\(descriptor.resourceName) should disable world_tutorial")
            }
        }
    }
}
