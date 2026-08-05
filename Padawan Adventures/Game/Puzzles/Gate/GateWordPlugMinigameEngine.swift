import Foundation

nonisolated enum GateWordPlugEngineEvent: Equatable, Sendable {
    case playWordSound(trackID: String)
    case playLetterName(trackID: String)
    case playLetterSound(trackID: String)
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
        var letters: [GateLetter]

        init(from puzzle: GateWordPlugConfig) {
            wordCountMin = puzzle.wordCountMin
            wordCountMax = puzzle.wordCountMax
            letterPosition = puzzle.letterPosition
            words = puzzle.words
            letters = puzzle.letters
        }

        init(
            wordCountMin: Int = 3,
            wordCountMax: Int = 6,
            letterPosition: GateWordPlugLetterPosition = .starting,
            words: [GateWord],
            letters: [GateLetter]
        ) {
            self.wordCountMin = wordCountMin
            self.wordCountMax = wordCountMax
            self.letterPosition = letterPosition
            self.words = GateSpellingConfig.normalizedWords(words)
            self.letters = GateLetterMatchConfig.normalizedLetters(letters)
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

    init(config: Config, rng: some RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.config = config
        self.rng = rng
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

        // Every word is eligible; the round size comes from the configured min/max.
        var pool = config.words
        pool.sort { $0.word < $1.word }

        let count = Self.sampleWordCount(
            minimum: config.wordCountMin,
            maximum: config.wordCountMax,
            poolSize: pool.count,
            rng: &rng
        )
        pool.shuffle(using: &rng)
        let chosen = Array(pool.prefix(count))

        slots = chosen.map { entry in
            WordSlot(
                id: UUID(),
                word: entry.word,
                imageName: entry.image,
                maskedText: config.letterPosition.maskedText(for: entry.word),
                wordTrackID: entry.sfx,
                letter: config.letterPosition.answerLetter(in: entry.word) ?? ""
            )
        }

        let letterByGlyph = Dictionary(uniqueKeysWithValues: config.letters.map { ($0.letter, $0) })
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
        return [.playLetterSound(trackID: token.pronunciationTrackID)]
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

    /// Uniform pick in `[minimum, maximum]`, clamped to the pool and `maxWordsPerRound`.
    /// When that range contains a multiple of 3, snaps to the nearest one still in range
    /// (ties prefer the lower value) so 3-column boards stay balanced when possible.
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

        let chosen = Int.random(in: lo...hi, using: &rng)
        return Self.nearestMultipleOfThree(to: chosen, in: lo...hi) ?? chosen
    }

    /// Nearest multiple of 3 in `range` to `value`, if any. Ties prefer the lower multiple.
    static func nearestMultipleOfThree(to value: Int, in range: ClosedRange<Int>) -> Int? {
        let lo = range.lowerBound
        let hi = range.upperBound
        let first = lo.isMultiple(of: 3) ? lo : lo + (3 - lo % 3)
        guard first <= hi else { return nil }

        var best = first
        var bestDistance = abs(value - first)
        var candidate = first + 3
        while candidate <= hi {
            let distance = abs(value - candidate)
            if distance < bestDistance {
                best = candidate
                bestDistance = distance
            }
            candidate += 3
        }
        return best
    }
}
