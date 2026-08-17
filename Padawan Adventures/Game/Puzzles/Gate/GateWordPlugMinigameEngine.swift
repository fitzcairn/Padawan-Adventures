import Foundation

nonisolated enum GateWordPlugEngineEvent: Equatable, Sendable {
    case playWordSound(trackID: String)
    case playGraphemeName(trackID: String)
    case playGraphemeSound(trackID: String)
    case correctPlug(slotID: UUID, letterID: UUID)
    case playCorrect
    case incorrectPlug(letterID: UUID)
    case won
}

/// Pure gate word-plug puzzle session rules (word pick, plug matching).
nonisolated struct GateWordPlugMinigameEngine {
    nonisolated struct Config: Equatable, Sendable {
        var wordCountMin: Int
        var wordCountMax: Int
        var letterPosition: GateWordPlugLetterPosition
        var words: [GateWord]
        var graphemes: [GateGrapheme]
        var vocabulary: LevelVocabularyPool

        init(from puzzle: GateWordPlugConfig) {
            wordCountMin = puzzle.wordCountMin
            wordCountMax = puzzle.wordCountMax
            letterPosition = puzzle.letterPosition
            words = puzzle.words
            graphemes = puzzle.graphemes
            vocabulary = puzzle.vocabulary
        }

        init(
            wordCountMin: Int = 3,
            wordCountMax: Int = 6,
            letterPosition: GateWordPlugLetterPosition = .starting,
            words: [GateWord],
            graphemes: [GateGrapheme],
            vocabulary: LevelVocabularyPool? = nil
        ) {
            self.wordCountMin = wordCountMin
            self.wordCountMax = wordCountMax
            self.letterPosition = letterPosition
            self.words = GateWord.normalized(words)
            self.graphemes = GateGraphemeMatchConfig.normalizedGraphemes(graphemes)
            self.vocabulary = vocabulary ?? LevelVocabularyPool.singleTier(
                words: self.words,
                graphemes: self.graphemes
            )
        }
    }

    /// One word plate plus its socket.
    nonisolated struct WordSlot: Equatable, Sendable, Identifiable {
        let id: UUID
        let word: String
        /// Optional sprite basename under `Sprites/Words/`.
        let imageName: String?
        let maskedText: String
        let wordTrackID: String
        let letter: String
    }

    /// One draggable letter part in the tray.
    nonisolated struct LetterToken: Equatable, Sendable, Identifiable {
        let id: UUID
        let letter: String
        let nameTrackID: String
        let pronunciationTrackID: String
    }

    let config: Config
    private(set) var isActive = false
    private(set) var isFrozen = false
    private(set) var slots: [WordSlot] = []
    private(set) var tray: [LetterToken] = []
    /// slotID → letterID for solved pairs.
    private(set) var plugged: [UUID: UUID] = [:]
    private(set) var outcome: MinigameOutcome?

    private var rng: any RandomNumberGenerator
    private let sampler: LevelVocabularySampler

    init(
        config: Config,
        rng: some RandomNumberGenerator = SystemRandomNumberGenerator(),
        sampler: LevelVocabularySampler? = nil
    ) {
        self.config = config
        self.rng = rng
        self.sampler = sampler ?? LevelVocabularySampler(pool: config.vocabulary)
    }

    func slot(id: UUID) -> WordSlot? {
        slots.first { $0.id == id }
    }

    func token(id: UUID) -> LetterToken? {
        tray.first { $0.id == id }
    }

    func isSlotFilled(_ id: UUID) -> Bool {
        plugged[id] != nil
    }

    func isTokenPlugged(_ id: UUID) -> Bool {
        plugged.values.contains(id)
    }

    mutating func begin() {
        isActive = true
        isFrozen = false
        outcome = nil
        plugged = [:]

        let count = Self.sampleWordCount(
            minimum: config.wordCountMin,
            maximum: config.wordCountMax,
            poolSize: distinctAnswerCount,
            rng: &rng
        )
        let chosen = pickWordsWithDistinctAnswers(count: count)

        slots = chosen.map { entry in
            WordSlot(
                id: UUID(),
                word: entry.word,
                imageName: entry.image,
                maskedText: config.letterPosition.maskedText(for: entry),
                wordTrackID: entry.sfx,
                letter: config.letterPosition.answerGrapheme(in: entry) ?? ""
            )
        }

        let letterByGlyph = Dictionary(uniqueKeysWithValues: config.graphemes.map { ($0.grapheme, $0) })
        tray = slots.map { slot in
            if let entry = letterByGlyph[slot.letter] {
                return LetterToken(
                    id: UUID(),
                    letter: slot.letter,
                    nameTrackID: entry.name,
                    pronunciationTrackID: entry.pronunciation
                )
            }
            let name = LetterSoundCatalog.nameTrackID(for: slot.letter)
                ?? "sfx_letter_\(slot.letter)_name"
            let pronunciation = LetterSoundCatalog.pronunciationTrackID(for: slot.letter)
                ?? "sfx_letter_\(slot.letter)_pronunciation"
            return LetterToken(
                id: UUID(),
                letter: slot.letter,
                nameTrackID: name,
                pronunciationTrackID: pronunciation
            )
        }
        tray.shuffle(using: &rng)
    }

    mutating func end() {
        isActive = false
        isFrozen = true
    }

    mutating func tapWord(slotID: UUID) -> [GateWordPlugEngineEvent] {
        guard isActive, !isFrozen else { return [] }
        guard let slot = slot(id: slotID) else { return [] }
        return [.playWordSound(trackID: slot.wordTrackID)]
    }

    /// Pronunciation cue when a tray plug is touched / picked up.
    mutating func tapLetter(id: UUID) -> [GateWordPlugEngineEvent] {
        guard isActive, !isFrozen else { return [] }
        guard let token = token(id: id), !isTokenPlugged(id) else { return [] }
        return [.playGraphemeSound(trackID: token.pronunciationTrackID)]
    }

    mutating func plug(letterID: UUID, intoSlotID: UUID) -> [GateWordPlugEngineEvent] {
        guard isActive, !isFrozen, outcome == nil else { return [] }
        guard let slot = slot(id: intoSlotID), !isSlotFilled(intoSlotID),
              let token = token(id: letterID), !isTokenPlugged(letterID) else {
            return []
        }

        guard token.letter == slot.letter else {
            return [.incorrectPlug(letterID: letterID)]
        }

        plugged[slot.id] = token.id
        var events: [GateWordPlugEngineEvent] = [
            .correctPlug(slotID: slot.id, letterID: token.id),
            .playWordSound(trackID: slot.wordTrackID),
            .playCorrect,
        ]
        if plugged.count >= slots.count {
            isFrozen = true
            outcome = .won(starsAwarded: slots.count)
            events.append(.won)
        }
        return events
    }

    /// How many different answer graphemes the pool can supply. The tray holds one plug
    /// per slot, so a larger board would have to repeat a letter.
    private var distinctAnswerCount: Int {
        let source = config.vocabulary.allWords.isEmpty ? config.words : config.vocabulary.allWords
        return Set(source.compactMap { config.letterPosition.answerGrapheme(in: $0) }).count
    }

    /// Draws up to `count` words, at most one per answer grapheme. Returns fewer words
    /// when the pool runs out of unused answers.
    private mutating func pickWordsWithDistinctAnswers(count: Int) -> [GateWord] {
        var chosen: [GateWord] = []
        var usedAnswers = Set<String>()
        var didRefill = false
        let letterPosition = config.letterPosition
        while chosen.count < count {
            var localRng = rng
            let matches: (GateWord) -> Bool = { entry in
                guard let answer = letterPosition.answerGrapheme(in: entry) else {
                    return false
                }
                return !usedAnswers.contains(answer)
            }
            var picked = sampler.nextWord(where: matches, refillWhenEmpty: false, using: &localRng)
            if picked == nil, !didRefill {
                picked = sampler.nextWord(where: matches, refillWhenEmpty: true, using: &localRng)
                didRefill = true
            }
            rng = localRng
            guard let entry = picked,
                  let answer = letterPosition.answerGrapheme(in: entry) else {
                break
            }
            chosen.append(entry)
            usedAnswers.insert(answer)
        }
        return chosen
    }

    /// Reorders unplugged tray letters after a wrong drop. Same tokens; new order.
    /// Retries until the remaining order changes when more than one letter is left.
    mutating func shuffleRemainingTray() {
        let remainingIndices = tray.indices.filter { !isTokenPlugged(tray[$0].id) }
        guard remainingIndices.count > 1 else { return }
        var remaining = remainingIndices.map { tray[$0] }
        let before = remaining.map(\.id)
        for _ in 0..<8 {
            remaining.shuffle(using: &rng)
            if remaining.map(\.id) != before { break }
        }
        for (offset, index) in remainingIndices.enumerated() {
            tray[index] = remaining[offset]
        }
    }

    /// Uniform pick in `[minimum, maximum]`, clamped to the pool and `maxWordsPerRound`.
    static func sampleWordCount(
        minimum: Int,
        maximum: Int,
        poolSize: Int,
        rng: inout some RandomNumberGenerator
    ) -> Int {
        let cap = min(max(poolSize, 1), GateWordPlugConfig.maxWordsPerRound)
        let lo = max(1, min(minimum, maximum))
        let hi = min(max(minimum, maximum), cap)
        guard lo <= hi else { return cap }
        return Int.random(in: lo...hi, using: &rng)
    }
}
