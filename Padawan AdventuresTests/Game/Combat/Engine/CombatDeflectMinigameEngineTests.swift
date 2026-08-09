import Testing
@testable import Padawan_Adventures

struct CombatDeflectMinigameEngineTests {
    private func letters(_ values: [String]) -> [GateGrapheme] {
        values.map {
            GateGrapheme(
                grapheme: $0,
                pronunciation: "sfx_letter_\($0)_pronunciation",
                name: "sfx_letter_\($0)_name"
            )
        }
    }

    /// Imaged words covering a…f so configured ring letters always have a throw candidate.
    private func words(for letters: [String]) -> [GateWord] {
        let samples: [String: [String]] = [
            "a": ["ant"],
            "b": ["bed", "boat", "bug"],
            "c": ["can", "cat", "coat"],
            "d": ["dad", "dog"],
            "e": ["egg"],
            "f": ["fish"],
        ]
        return letters.flatMap { letter in
            (samples[letter] ?? ["\(letter)at"]).map {
                WordCatalog.imagedFallbackEntry(word: $0)
            }
        }
    }

    private func makeEngine(
        monsterHP: Int = 3,
        startingHealth: Int = 3,
        orbTravelSeconds: Double = 3,
        pool: [String] = ["a", "b", "c"],
        wordPool: [GateWord]? = nil,
        seed: UInt64 = 42,
        letterPosition: GateWordPlugLetterPosition = .starting,
        isPlausibleSpelling: @escaping @Sendable (String) -> Bool = { _ in false }
    ) -> CombatDeflectMinigameEngine {
        var engine = CombatDeflectMinigameEngine(
            config: .init(
                graphemes: letters(pool),
                words: wordPool ?? words(for: pool),
                monsterHP: monsterHP,
                orbTravelSeconds: orbTravelSeconds,
                letterPosition: letterPosition
            ),
            startingHealth: startingHealth,
            rng: CombatSeededGenerator(seed: seed),
            isPlausibleSpelling: isPlausibleSpelling
        )
        engine.begin()
        return engine
    }

    /// Pulls the orb's ring out of the throw event so tests can answer correctly.
    private func ring(in events: [CombatDeflectEvent]) -> CombatDeflectRing? {
        for event in events {
            if case .throwOrb(_, _, _, _, let ring, _) = event { return ring }
        }
        return nil
    }

    @Test func beginStartsFullHealthAndFullMonsterHP() {
        let engine = makeEngine(monsterHP: 5, startingHealth: 3)
        #expect(engine.healthCount == 3)
        #expect(engine.monsterHP == 5)
        #expect(engine.activeOrb == nil)
        #expect(engine.outcome == nil)
        #expect(!engine.hasWon)
        #expect(!engine.hasLost)
    }

    @Test func oneHitPointMonsterDiesOnFirstDeflect() {
        var engine = makeEngine(monsterHP: 1)
        let thrown = engine.throwNextOrb()
        guard let ring = ring(in: thrown) else {
            #expect(Bool(false), "no orb thrown")
            return
        }
        #expect(engine.registerTap(ring: ring) == .correct(ring))
        let events = engine.registerOrbReachedMonster()
        #expect(events.contains(.monsterHealthChanged(0)))
        #expect(events.contains(.won(starsAwarded: 1)))
    }

    @Test func throwEmitsOrbAndSpokenWord() {
        var engine = makeEngine()
        let events = engine.throwNextOrb()
        #expect(events.count == 2)

        guard case .throwOrb(_, let letter, let word, let sfx, let ring, let travel) = events[0]
        else {
            Issue.record("expected a throwOrb event first")
            return
        }
        #expect(travel == 3)
        #expect(["a", "b", "c"].contains(letter))
        // The orb's letter must be the letter on the ring that deflects it.
        #expect(engine.config.graphemes[ring.rawValue].grapheme == letter)
        #expect(word.hasPrefix(letter))
        #expect(sfx == "sfx_word_\(word)")
        #expect(events[1] == .speakWord(trackID: "sfx_word_\(word)"))
        #expect(engine.activeOrb?.letter == letter)
        #expect(engine.activeOrb?.word == word)
        #expect(engine.activeOrb?.isResolved == false)
    }

    @Test func throwPicksAWordStartingWithTheRingLetter() {
        let wordPool = [
            WordCatalog.imagedFallbackEntry(word: "bed"),
            WordCatalog.imagedFallbackEntry(word: "boat"),
            WordCatalog.imagedFallbackEntry(word: "bug"),
        ]
        var seen: Set<String> = []
        for seed in UInt64(1)...40 {
            var engine = makeEngine(pool: ["b"], wordPool: wordPool, seed: seed)
            let events = engine.throwNextOrb()
            guard case .throwOrb(_, let letter, let word, _, _, _) = events.first else {
                Issue.record("expected a throw")
                return
            }
            #expect(letter == "b")
            #expect(word.hasPrefix("b"))
            seen.insert(word)
        }
        #expect(seen.count > 1)
        #expect(seen.isSubset(of: ["bed", "boat", "bug"]))
    }

    @Test func throwSkipsLettersWithNoImagedWord() {
        var engine = makeEngine(
            monsterHP: 500,
            pool: ["a", "g"],
            wordPool: [WordCatalog.imagedFallbackEntry(word: "ant")],
            seed: 1
        )
        for _ in 0..<20 {
            let events = engine.throwNextOrb()
            guard case .throwOrb(_, let letter, _, _, _, _) = events.first else {
                Issue.record("expected a throw")
                return
            }
            #expect(letter == "a")
            _ = engine.registerOrbReachedMonster()
        }
    }

    @Test func endingPositionThrowsWordsEndingWithTheRingGrapheme() {
        let wordPool = [
            WordCatalog.imagedFallbackEntry(word: "boat"),
            WordCatalog.imagedFallbackEntry(word: "cat"),
            WordCatalog.imagedFallbackEntry(word: "coat"),
            WordCatalog.imagedFallbackEntry(word: "web"),
        ]
        var engine = makeEngine(
            monsterHP: 500,
            pool: ["t", "d"],
            wordPool: wordPool,
            seed: 7,
            letterPosition: .ending
        )
        for _ in 0..<40 {
            let events = engine.throwNextOrb()
            guard case .throwOrb(_, let letter, let word, _, let ring, _) = events.first else {
                Issue.record("expected a throw")
                return
            }
            #expect(["t", "d"].contains(letter))
            #expect(engine.config.graphemes[ring.rawValue].grapheme == letter)
            #expect(word.hasSuffix(letter))
            _ = engine.registerOrbReachedMonster()
        }
    }

    @Test func endingPositionSkipsGraphemesWithNoMatchingWord() {
        var engine = makeEngine(
            monsterHP: 500,
            pool: ["a", "t"],
            wordPool: [WordCatalog.imagedFallbackEntry(word: "cat")],
            seed: 1,
            letterPosition: .ending
        )
        for _ in 0..<20 {
            let events = engine.throwNextOrb()
            guard case .throwOrb(_, let letter, _, _, _, _) = events.first else {
                Issue.record("expected a throw")
                return
            }
            #expect(letter == "t")
            _ = engine.registerOrbReachedMonster()
        }
    }

    @Test func endingMatchUsesGraphemeUnitNotStringSuffix() {
        let config = CombatDeflectMinigameEngine.Config(
            graphemes: letters(["t", "st"]),
            words: [
                WordCatalog.imagedFallbackEntry(word: "fast", graphemes: ["f", "a", "st"]),
            ],
            monsterHP: 3,
            orbTravelSeconds: 3,
            letterPosition: .ending
        )
        #expect(config.words(matching: "st").map(\.word) == ["fast"])
        #expect(config.words(matching: "t").isEmpty)
    }

    @Test func onlyOneOrbCanBeLiveAtATime() {
        var engine = makeEngine()
        #expect(!engine.throwNextOrb().isEmpty)
        #expect(engine.throwNextOrb().isEmpty)
    }

    @Test func throwDoesNothingBeforeBeginOrAfterEnd() {
        var engine = CombatDeflectMinigameEngine(
            config: .init(
                graphemes: letters(["a", "b", "c"]),
                words: words(for: ["a", "b", "c"]),
                monsterHP: 2,
                orbTravelSeconds: 1
            ),
            startingHealth: 3,
            rng: CombatSeededGenerator(seed: 7)
        )
        #expect(engine.throwNextOrb().isEmpty)
        engine.begin()
        #expect(!engine.throwNextOrb().isEmpty)
        engine.end()
        #expect(engine.registerOrbReachedMonster().isEmpty)
    }

    @Test func correctTapMarksOrbResolvedAndSecondTapIsIgnored() {
        var engine = makeEngine()
        let events = engine.throwNextOrb()
        guard let target = ring(in: events) else {
            Issue.record("expected a thrown orb")
            return
        }
        #expect(engine.registerTap(ring: target) == .correct(target))
        #expect(engine.activeOrb?.isResolved == true)
        // A double-tap must not fire the consequence twice.
        #expect(engine.registerTap(ring: target) == .ignored)
    }

    @Test func wrongTapReportsTheTappedRingAndLeavesOrbUnresolved() {
        var engine = makeEngine()
        let events = engine.throwNextOrb()
        guard let target = ring(in: events) else {
            Issue.record("expected a thrown orb")
            return
        }
        guard let wrong = engine.rings.first(where: { $0 != target }) else {
            Issue.record("expected another ring to exist")
            return
        }
        #expect(engine.registerTap(ring: wrong) == .wrong(wrong))
        #expect(engine.activeOrb?.isResolved == false)
        // The player can keep trying until they hit the matching ring.
        #expect(engine.registerTap(ring: target) == .correct(target))
        #expect(engine.activeOrb?.isResolved == true)
    }

    @Test func tapWithNoLiveOrbIsIgnored() {
        var engine = makeEngine()
        #expect(engine.registerTap(ring: CombatDeflectRing(1)) == .ignored)
    }

    @Test func deflectedOrbDrainsMonsterHP() {
        var engine = makeEngine(monsterHP: 3)
        _ = engine.throwNextOrb()
        let events = engine.registerOrbReachedMonster()
        #expect(events == [.monsterHealthChanged(2)])
        #expect(engine.monsterHP == 2)
        #expect(engine.activeOrb == nil)
        #expect(engine.outcome == nil)
    }

    @Test func drainingMonsterHPToZeroWinsAndAwardsStarsEqualToMaxHP() {
        var engine = makeEngine(monsterHP: 2)
        _ = engine.throwNextOrb()
        _ = engine.registerOrbReachedMonster()
        _ = engine.throwNextOrb()
        let events = engine.registerOrbReachedMonster()

        #expect(events == [.monsterHealthChanged(0), .won(starsAwarded: 2)])
        #expect(engine.monsterHP == 0)
        #expect(engine.hasWon)
        #expect(engine.outcome == .won(starsAwarded: 2))
    }

    @Test func orbHittingPlayerCostsAHeart() {
        var engine = makeEngine(startingHealth: 3)
        _ = engine.throwNextOrb()
        let events = engine.registerOrbHitPlayer()
        #expect(events == [.playerHealthChanged(2)])
        #expect(engine.healthCount == 2)
        #expect(engine.activeOrb == nil)
        #expect(!engine.hasLost)
    }

    @Test func losingLastHeartEndsTheFight() {
        var engine = makeEngine(startingHealth: 1)
        _ = engine.throwNextOrb()
        let events = engine.registerOrbHitPlayer()
        #expect(events == [.playerHealthChanged(0), .lost])
        #expect(engine.hasLost)
        #expect(engine.outcome == .lost)
    }

    @Test func noEventsAfterTheOutcomeIsDecided() {
        var engine = makeEngine(monsterHP: 1)
        _ = engine.throwNextOrb()
        #expect(engine.registerOrbReachedMonster() == [
            .monsterHealthChanged(0),
            .won(starsAwarded: 1),
        ])
        // A late animation callback must not resurrect the fight.
        #expect(engine.throwNextOrb().isEmpty)
        #expect(engine.registerOrbHitPlayer().isEmpty)
        #expect(engine.registerTap(ring: CombatDeflectRing(1)) == .ignored)
        #expect(engine.monsterHP == 0)
    }

    @Test func registerCallbacksWithoutALiveOrbAreNoOps() {
        var engine = makeEngine(monsterHP: 3, startingHealth: 3)
        #expect(engine.registerOrbReachedMonster().isEmpty)
        #expect(engine.registerOrbHitPlayer().isEmpty)
        #expect(engine.monsterHP == 3)
        #expect(engine.healthCount == 3)
    }

    @Test func configClampsDegenerateValues() {
        let config = CombatDeflectMinigameEngine.Config(
            graphemes: letters(["a", "b", "c"]),
            words: words(for: ["a", "b", "c"]),
            monsterHP: 0,
            orbTravelSeconds: 0
        )
        #expect(config.monsterHP == 1)
        #expect(config.orbTravelSeconds == 0.2)
    }

    @Test func everyRingIsEventuallyTargetedAcrossManyThrows() {
        var engine = makeEngine(monsterHP: 500, seed: 99)
        var seen = Set<CombatDeflectRing>()
        for _ in 0..<200 {
            guard let ring = ring(in: engine.throwNextOrb()) else { break }
            seen.insert(ring)
            _ = engine.registerOrbReachedMonster()
        }
        #expect(seen == Set(engine.rings))
    }

    @Test func nextThrowExcludesTheLastDeflectedLetter() {
        var engine = makeEngine(monsterHP: 500, seed: 11)
        var previous: CombatDeflectRing?
        for _ in 0..<100 {
            guard let ring = ring(in: engine.throwNextOrb()) else {
                Issue.record("expected a thrown orb")
                return
            }
            if let previous {
                #expect(ring != previous, "deflected letter must not repeat on the next throw")
            }
            previous = ring
            _ = engine.registerOrbReachedMonster()
        }
    }

    @Test(arguments: [2, 6])
    func supportsConfiguredRingCounts(count: Int) {
        let pool = Array("abcdef").prefix(count).map(String.init)
        var engine = makeEngine(monsterHP: 500, pool: pool, seed: 5)
        #expect(engine.config.ringCount == count)
        #expect(engine.rings.count == count)
        var seen = Set<CombatDeflectRing>()
        for _ in 0..<120 {
            guard let ring = ring(in: engine.throwNextOrb()) else { break }
            seen.insert(ring)
            _ = engine.registerOrbReachedMonster()
        }
        #expect(seen == Set(engine.rings))
    }

    @Test func ringIndicesMapLeftToRight() {
        let rings = CombatDeflectRing.all(count: 3)
        #expect(rings.map(\.index) == [0, 1, 2])
        #expect(rings.count == 3)
    }

    /// Regression: the default collision check must leave Level-1 ending combat with
    /// throw candidates. A full English dictionary check emptied this pool and hung
    /// the first-encounter tutorial (no orb → demo never finishes).
    @Test func defaultSpellingCheckKeepsTythonEndingThrowPoolAlive() {
        let words = ["at", "it", "in", "an", "sat", "sit", "pat", "tap", "pan", "nap", "pin", "sip"].map {
            WordCatalog.imagedFallbackEntry(word: $0)
        }
        let config = CombatDeflectMinigameEngine.Config(
            graphemes: letters(["t", "p", "n"]),
            words: words,
            monsterHP: 5,
            orbTravelSeconds: 3,
            letterPosition: .ending
        )
        let throwable = ["t", "p", "n"].flatMap { config.throwWords(matching: $0).map(\.word) }
        #expect(!throwable.isEmpty)
        #expect(Set(throwable).isSubset(of: ["sat", "tap", "nap", "pin"]))

        var engine = CombatDeflectMinigameEngine(config: config, startingHealth: 3)
        engine.begin()
        #expect(!engine.throwNextOrb().isEmpty)
    }

    @Test func defaultSpellingCheckRejectsTripBesideTris() {
        let tris = WordCatalog.imagedFallbackEntry(word: "tris", graphemes: ["tr", "i", "s"])
        let config = CombatDeflectMinigameEngine.Config(
            graphemes: letters(["s", "p"]),
            words: [tris, WordCatalog.imagedFallbackEntry(word: "tap")],
            monsterHP: 5,
            orbTravelSeconds: 3,
            letterPosition: .ending
        )
        #expect(config.throwWords(matching: "s").isEmpty)
        #expect(config.throwWords(matching: "p").map(\.word) == ["tap"])
        #expect(CombatDeflectMinigameEngine.isPlausibleSpelling("trip"))
        #expect(!CombatDeflectMinigameEngine.isPlausibleSpelling("tip"))
    }

    @Test func throwSkipsWordsWithAmbiguousRingAnswers() {
        let wordPool = [
            WordCatalog.imagedFallbackEntry(word: "sit"),
            WordCatalog.imagedFallbackEntry(word: "sip"),
            WordCatalog.imagedFallbackEntry(word: "tap"),
        ]
        var engine = makeEngine(
            monsterHP: 500,
            pool: ["t", "p"],
            wordPool: wordPool,
            seed: 3,
            letterPosition: .ending
        )
        var seen = Set<String>()
        for _ in 0..<30 {
            let events = engine.throwNextOrb()
            guard case .throwOrb(_, let letter, let word, _, _, _) = events.first else {
                Issue.record("expected a throw")
                return
            }
            #expect(letter == "p")
            #expect(word == "tap")
            seen.insert(word)
            _ = engine.registerOrbReachedMonster()
        }
        #expect(seen == ["tap"])
    }

    @Test func throwSkipsWordsWithPlausibleAlternateSpellings() {
        let wordPool = [
            WordCatalog.imagedFallbackEntry(word: "tris", graphemes: ["tr", "i", "s"]),
            WordCatalog.imagedFallbackEntry(word: "tap"),
        ]
        var engine = makeEngine(
            monsterHP: 500,
            pool: ["s", "p"],
            wordPool: wordPool,
            seed: 9,
            letterPosition: .ending,
            isPlausibleSpelling: { $0 == "trip" }
        )
        for _ in 0..<20 {
            let events = engine.throwNextOrb()
            guard case .throwOrb(_, let letter, let word, _, _, _) = events.first else {
                Issue.record("expected a throw")
                return
            }
            #expect(letter == "p")
            #expect(word == "tap")
            _ = engine.registerOrbReachedMonster()
        }
    }

    @Test func throwAvoidsDuplicateWordsUntilPoolExhausted() {
        let wordPool = [
            WordCatalog.imagedFallbackEntry(word: "bed"),
            WordCatalog.imagedFallbackEntry(word: "boat"),
            WordCatalog.imagedFallbackEntry(word: "bug"),
        ]
        var engine = makeEngine(
            monsterHP: 500,
            pool: ["b"],
            wordPool: wordPool,
            seed: 1
        )
        var firstPass: [String] = []
        for _ in 0..<3 {
            let events = engine.throwNextOrb()
            guard case .throwOrb(_, _, let word, _, _, _) = events.first else {
                Issue.record("expected a throw")
                return
            }
            firstPass.append(word)
            _ = engine.registerOrbReachedMonster()
        }
        #expect(Set(firstPass) == ["bed", "boat", "bug"])

        // After every unique word has been used, repeats are allowed.
        let events = engine.throwNextOrb()
        guard case .throwOrb(_, _, let word, _, _, _) = events.first else {
            Issue.record("expected a throw after exhaustion")
            return
        }
        #expect(["bed", "boat", "bug"].contains(word))
    }
}
