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
            #expect(level.name == descriptor.nameStringID)
            #expect(Strings.text(level.name) == descriptor.displayName)
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

        #expect(level.name == "level_tython")
        #expect(Strings.text(level.name) == "Tython")
        #expect(level.order == 1)
        #expect(level.worldTutorial)
        #expect(level.color == "#2E7D32")
        #expect(level.artifact == "leaf.fill")
        #expect(level.treasure == "emitter")
        #expect(level.floor.set == "1-tython")
        #expect(level.letters.set == "1-tython")
        #expect(level.sprite?.root == "Levels/1-tython")
        #expect(level.width == 35)
        #expect(level.roomCount == 15)
        #expect(level.room.minRoomSize == 4)
        #expect(level.room.maxRoomSize == 7)
        #expect(level.room.shape == .organic)
        #expect(level.enemies?.types == ["dino", "treant"])
        #expect(level.currentLevelProbability == 0.75)
        #expect(level.vocabulary.allWords.map(\.word) == Self.level1Words)
        #expect(level.vocabulary.allGraphemes.map(\.grapheme) == ["s", "a", "t", "p", "i", "n"])
        #expect(level.vocabulary.letters == Self.level1Graphemes)

        #expect(level.combat.minigames.map(\.kind) == [
            .slash, .startingSoundDeflect, .endingSoundDeflect,
        ])
        #expect(level.combat.minigames.map(\.weight) == [1.0, 1.0, 1.0])
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
        #expect(deflect.graphemes.map(\.grapheme) == ["s", "a", "t", "p", "i", "n"])
        guard case .deflect(let endingDeflect) = level.combat.minigames[2] else {
            Issue.record("expected ending-sound deflect combat entry")
            return
        }
        #expect(endingDeflect.letterPosition == .ending)
        #expect(endingDeflect.monsterHP == 5)
        #expect(endingDeflect.orbTravelSeconds == 8)
        #expect(endingDeflect.ringCount == 3)
        // Level 1 ending candidates are t/p/n only; ring_count clamps to 3.
        #expect(endingDeflect.graphemes.map(\.grapheme) == ["t", "p", "n"])

        #expect(level.gate.minigameChance == 1.0)
        #expect(level.gate.fx.trackID(for: "opened") == "gate-open")
        #expect(level.gate.minigames.map(\.kind) == [.wordPlug, .endingSoundPlug, .soundOutWord, .graphemeMatch])
        #expect(level.gate.minigames.map(\.weight) == [1, 1, 1, 1])
        guard case .graphemeMatch(let graphemeMatch) = level.gate.minigames[3] else {
            Issue.record("expected grapheme-sound gate entry")
            return
        }
        #expect(graphemeMatch.graphemeCase == .lower)
        #expect(graphemeMatch.graphemeSoundRepeatSeconds == 3)
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
        #expect(level.pit.minigames.map(\.weight) == [1, 1, 1])
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

    @Test func shippedLevelsUseExpectedRoomShapesAndSizes() throws {
        let expected: [String: (shape: LevelConfig.RoomShape, min: Int, max: Int)] = [
            "1-tython": (.organic, 4, 7),
            "2-tatooine": (.roundIsh, 5, 8),
            "3-ilum": (.roundIsh, 5, 7),
            "4-kashyyyk": (.organic, 5, 7),
            "5-dagobah": (.organic, 5, 7),
            "6-coruscant": (.rect, 4, 6),
            "7-mustafar": (.organic, 4, 6),
            "8-geonosis": (.roundIsh, 5, 7),
        ]
        let catalog = LevelCatalog.loadFromBundle()
        #expect(catalog.count == expected.count)
        for descriptor in catalog {
            guard let want = expected[descriptor.resourceName] else {
                Issue.record("unexpected level \(descriptor.resourceName)")
                continue
            }
            let level = try LevelConfig.loadFromBundle(
                named: descriptor.resourceName,
                subdirectory: LevelCatalog.subdirectory
            )
            #expect(level.room.shape == want.shape, "\(descriptor.resourceName) shape")
            #expect(level.room.minRoomSize == want.min, "\(descriptor.resourceName) min")
            #expect(level.room.maxRoomSize == want.max, "\(descriptor.resourceName) max")
        }
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

    @Test func levelsAfterIlumLaunchMoreSlashDecoys() throws {
        let catalog = LevelCatalog.loadFromBundle()
        #expect(!catalog.isEmpty)
        for descriptor in catalog {
            let level = try LevelConfig.loadFromBundle(
                named: descriptor.resourceName,
                subdirectory: LevelCatalog.subdirectory
            )
            guard case .slash(let slash) = level.combat.minigames.first else {
                Issue.record("expected slash combat on \(descriptor.resourceName)")
                continue
            }
            #expect(slash.minDecoyCount == 2, "\(descriptor.resourceName) min decoys")
            if descriptor.order <= 3 {
                #expect(slash.maxDecoyCount == 4, "\(descriptor.resourceName) max decoys")
            } else {
                #expect(slash.maxDecoyCount == 6, "\(descriptor.resourceName) max decoys")
            }
        }
    }

    @Test func levelsAfterTythonUseBothGraphemeCases() throws {
        let catalog = LevelCatalog.loadFromBundle()
        #expect(!catalog.isEmpty)
        for descriptor in catalog {
            let level = try LevelConfig.loadFromBundle(
                named: descriptor.resourceName,
                subdirectory: LevelCatalog.subdirectory
            )
            guard case .slash(let slash) = level.combat.minigames.first else {
                Issue.record("expected slash combat on \(descriptor.resourceName)")
                continue
            }
            guard case .graphemeMatch(let gate) = level.gate.minigames.last else {
                Issue.record("expected grapheme-sound gate on \(descriptor.resourceName)")
                continue
            }
            if descriptor.order == 1 {
                #expect(slash.graphemeCase == .lower)
                #expect(gate.graphemeCase == .lower)
            } else {
                #expect(slash.graphemeCase == .both, "\(descriptor.resourceName) combat")
                #expect(gate.graphemeCase == .both, "\(descriptor.resourceName) gate")
            }
        }
    }

    @Test func tatooineVocabularyIsCumulativeAcrossMinigames() throws {
        let level = try LevelConfig.loadFromBundle(
            named: "2-tatooine",
            subdirectory: LevelCatalog.subdirectory
        )
        let words = Set(level.vocabulary.allWords.map(\.word))
        #expect(words.isSuperset(of: Self.level1Words))
        #expect(words.contains("dog"))
        #expect(words.contains("mad"))
        #expect(level.vocabulary.tiers.map(\.order) == [1, 2])
        #expect(level.vocabulary.tiers.last?.weight == 0.75)

        guard case .slash(let slash) = level.combat.minigames[0] else {
            Issue.record("expected grapheme-sound combat")
            return
        }
        let slashGraphemes = Set(slash.vocabulary.allGraphemes.map(\.grapheme))
        #expect(slashGraphemes.isSuperset(of: ["s", "a", "t", "p", "m", "d"]))
        #expect(slash.vocabulary.tiers.last?.weight == 0.75)

        guard case .deflect(let starting) = level.combat.minigames[1],
              case .deflect(let ending) = level.combat.minigames[2] else {
            Issue.record("expected starting and ending sound combat")
            return
        }
        #expect(Set(starting.words.map(\.word)).isSuperset(of: Self.level1Words))
        #expect(starting.words.contains(where: { $0.word == "dog" }))
        let startingGraphemes = Set(starting.graphemes.map(\.grapheme))
        #expect(startingGraphemes.isSuperset(of: ["s", "a", "t", "p", "d", "m"]))
        #expect(starting.ringCount == 4)
        #expect(Set(ending.words.map(\.word)).isSuperset(of: Self.level1Words))
        #expect(ending.words.contains(where: { $0.word == "dog" }))

        guard case .bridge(let endingPit) = level.pit.minigames[1],
              case .bridge(let startingPit) = level.pit.minigames[2] else {
            Issue.record("expected starting and ending sound pit")
            return
        }
        #expect(Set(endingPit.words.map(\.word)).isSuperset(of: Self.level1Words))
        #expect(endingPit.words.contains(where: { $0.word == "dog" }))
        #expect(Set(startingPit.words.map(\.word)).isSuperset(of: Self.level1Words))
        #expect(startingPit.words.contains(where: { $0.word == "dog" }))

        guard case .wordPlug(let startingGate) = level.gate.minigames[0],
              case .wordPlug(let endingGate) = level.gate.minigames[1] else {
            Issue.record("expected starting and ending sound gate")
            return
        }
        #expect(Set(startingGate.words.map(\.word)).isSuperset(of: Self.level1Words))
        #expect(startingGate.words.contains(where: { $0.word == "dog" }))
        #expect(Set(endingGate.words.map(\.word)).isSuperset(of: Self.level1Words))
        #expect(endingGate.words.contains(where: { $0.word == "dog" }))

        guard case .graphemeMatch(let graphemeGate) = level.gate.minigames[3] else {
            Issue.record("expected grapheme-sound gate")
            return
        }
        let gateGraphemes = Set(graphemeGate.vocabulary.allGraphemes.map(\.grapheme))
        #expect(gateGraphemes.isSuperset(of: ["s", "a", "t", "p", "m", "d"]))
        #expect(graphemeGate.vocabulary.tiers.last?.weight == 0.75)
    }
}
