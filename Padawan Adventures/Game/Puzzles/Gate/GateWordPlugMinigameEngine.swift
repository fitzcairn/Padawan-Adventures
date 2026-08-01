import Foundation

nonisolated enum GateWordPlugEngineEvent: Equatable, Sendable {
    case playWordSound(trackID: String)
    case playLetterName(trackID: String)
    case playLetterSound(trackID: String)
    case correctPlug(slotID: UUID, letterID: UUID)
    case playCorrect
    case speakPhrase(String)
    case incorrectPlug(letterID: UUID)
    case won
}

/// Pure gate word-plug puzzle session rules (word pick, plug matching).
nonisolated struct GateWordPlugMinigameEngine {
    nonisolated struct Config: Equatable, Sendable {
        var wordCountMin: Int
        var wordCountMax: Int
        var words: [GateWord]
        var letters: [GateLetter]

        init(from puzzle: GateWordPlugConfig) {
            wordCountMin = puzzle.wordCountMin
            wordCountMax = puzzle.wordCountMax
            words = puzzle.words
            letters = puzzle.letters
        }

        init(
            wordCountMin: Int = 2,
            wordCountMax: Int = 6,
            words: [GateWord],
            letters: [GateLetter]
        ) {
            self.wordCountMin = wordCountMin
            self.wordCountMax = wordCountMax
            self.words = GateSpellingConfig.normalizedWords(words)
            self.letters = GateLetterMatchConfig.normalizedLetters(letters)
        }
    }

    /// One word plate plus its socket.
    nonisolated struct WordSlot: Equatable, Sendable, Identifiable {
        let id: UUID
        let word: String
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
    private(set) var outcome: GateOutcome?

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

        var byFirst: [String: GateWord] = [:]
        for word in config.words {
            guard let first = word.word.first else { continue }
            let key = String(first).lowercased()
            if byFirst[key] == nil {
                byFirst[key] = word
            }
        }
        var uniquePool = Array(byFirst.values)
        uniquePool.sort { $0.word < $1.word }

        let count = Self.sampleWordCount(
            minimum: config.wordCountMin,
            maximum: config.wordCountMax,
            poolSize: uniquePool.count,
            rng: &rng
        )
        uniquePool.shuffle(using: &rng)
        let chosen = Array(uniquePool.prefix(count))

        slots = chosen.map { entry in
            let letter = String(entry.word.prefix(1)).lowercased()
            let rest = String(entry.word.dropFirst())
            return WordSlot(
                id: UUID(),
                word: entry.word,
                maskedText: "_\(rest)",
                wordTrackID: entry.spelling,
                letter: letter
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

    mutating func tapLetter(id: UUID) -> [GateWordPlugEngineEvent] {
        guard isActive, !isFrozen else { return [] }
        guard let token = token(id: id), !isTokenPlugged(id) else { return [] }
        return [
            .playLetterName(trackID: token.nameTrackID),
            .playLetterSound(trackID: token.pronunciationTrackID),
        ]
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
            .playCorrect,
            .speakPhrase("\(slot.word.capitalized) starts with \(slot.letter.uppercased())"),
        ]
        if plugged.count >= slots.count {
            isFrozen = true
            outcome = .won(starsAwarded: slots.count)
            events.append(.won)
        }
        return events
    }

    /// Uniform over even values in range, clamped to the pool and to `maxWordsPerRound`.
    static func sampleWordCount(
        minimum: Int,
        maximum: Int,
        poolSize: Int,
        rng: inout some RandomNumberGenerator
    ) -> Int {
        let cap = min(max(poolSize, 1), GateWordPlugConfig.maxWordsPerRound)
        var hi = min(max(minimum, maximum), cap)
        hi -= hi % 2
        guard hi >= 2 else { return cap }
        var lo = max(2, min(minimum, maximum))
        if !lo.isMultiple(of: 2) { lo += 1 }
        if lo > hi { lo = hi }
        let choices = (hi - lo) / 2 + 1
        return lo + Int.random(in: 0..<choices, using: &rng) * 2
    }
}
