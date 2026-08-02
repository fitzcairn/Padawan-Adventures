import Testing
@testable import Padawan_Adventures

struct CombatDeflectMinigameEngineTests {
    private func letters(_ values: [String]) -> [GateLetter] {
        values.map {
            GateLetter(
                letter: $0,
                pronunciation: "sfx_letter_\($0)_pronunciation",
                name: "sfx_letter_\($0)_name"
            )
        }
    }

    /// Imaged words covering a…f so configured ring letters always have a throw candidate.
    private func words(for letters: [String]) -> [GateWord] {
        let samples: [String: [String]] = [
            "a": ["apple"],
            "b": ["bath", "boat", "book"],
            "c": ["car", "cat", "cloud"],
            "d": ["dance", "dog"],
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
        seed: UInt64 = 42
    ) -> CombatDeflectMinigameEngine {
        var engine = CombatDeflectMinigameEngine(
            config: .init(
                letters: letters(pool),
                words: wordPool ?? words(for: pool),
                monsterHP: monsterHP,
                orbTravelSeconds: orbTravelSeconds
            ),
            startingHealth: startingHealth,
            rng: CombatSeededGenerator(seed: seed)
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

    @Test func throwEmitsOrbAndSpokenWord() {
        var engine = makeEngine()
        let events = engine.throwNextOrb()
        #expect(events.count == 2)

        guard case .throwOrb(_, let letter, let word, let imageName, let ring, let travel) = events[0]
        else {
            Issue.record("expected a throwOrb event first")
            return
        }
        #expect(travel == 3)
        #expect(["a", "b", "c"].contains(letter))
        // The orb's letter must be the letter on the ring that deflects it.
        #expect(engine.config.letters[ring.rawValue].letter == letter)
        #expect(word.hasPrefix(letter))
        #expect(imageName != nil)
        #expect(events[1] == .speakWord(trackID: "sfx_word_\(word)"))
        #expect(engine.activeOrb?.letter == letter)
        #expect(engine.activeOrb?.word == word)
        #expect(engine.activeOrb?.isResolved == false)
    }

    @Test func throwPicksAWordStartingWithTheRingLetter() {
        let wordPool = [
            WordCatalog.imagedFallbackEntry(word: "bath"),
            WordCatalog.imagedFallbackEntry(word: "boat"),
            WordCatalog.imagedFallbackEntry(word: "book"),
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
        #expect(seen.isSubset(of: ["bath", "boat", "book"]))
    }

    @Test func throwSkipsLettersWithNoImagedWord() {
        var engine = makeEngine(
            monsterHP: 500,
            pool: ["a", "g"],
            wordPool: [WordCatalog.imagedFallbackEntry(word: "apple")],
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

    @Test func onlyOneOrbCanBeLiveAtATime() {
        var engine = makeEngine()
        #expect(!engine.throwNextOrb().isEmpty)
        #expect(engine.throwNextOrb().isEmpty)
    }

    @Test func throwDoesNothingBeforeBeginOrAfterEnd() {
        var engine = CombatDeflectMinigameEngine(
            config: .init(
                letters: letters(["a", "b", "c"]),
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

    @Test func wrongTapReportsTheTappedRingAndResolvesTheOrb() {
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
        #expect(engine.registerTap(ring: target) == .ignored)
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
            letters: letters(["a", "b", "c"]),
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
        #expect(rings.count == CombatDeflectConfig.defaultRingCount)
    }
}
