import Foundation

/// Shared word-pick and letter-bag logic for gate and pit spelling minigames.
nonisolated enum SpellingMinigameCore {
    nonisolated struct LetterToken: Equatable, Sendable, Identifiable {
        let id: UUID
        /// Single lowercase letter.
        let letter: String
    }

    private static let alphabet = Array("abcdefghijklmnopqrstuvwxyz").map(String.init)

    static func pickTargetEntry(
        from words: [GateWord],
        fallbackWord: String,
        using rng: inout some RandomNumberGenerator
    ) -> GateWord {
        guard !words.isEmpty else {
            return .fallbackEntry(word: fallbackWord)
        }
        let index = Int.random(in: 0..<words.count, using: &rng)
        return words[index]
    }

    /// One token per word character, plus `numPaddingLetters` random decoys, shuffled.
    static func buildLetterBag(
        for word: String,
        numPaddingLetters: Int,
        using rng: inout some RandomNumberGenerator
    ) -> [LetterToken] {
        let targetCount = word.count + numPaddingLetters
        var bag: [LetterToken] = word.map { character in
            LetterToken(id: UUID(), letter: String(character).lowercased())
        }
        while bag.count < targetCount {
            let index = Int.random(in: 0..<Self.alphabet.count, using: &rng)
            bag.append(LetterToken(id: UUID(), letter: Self.alphabet[index]))
        }
        bag.shuffle(using: &rng)
        return bag
    }

    /// Pit spelling keeps word-occurrence token IDs in spelling order (excludes decoys).
    static func buildLetterBagWithWordIDs(
        for word: String,
        numPaddingLetters: Int,
        using rng: inout some RandomNumberGenerator
    ) -> (letters: [LetterToken], wordLetterIDs: [UUID]) {
        let wordTokens: [LetterToken] = word.map { character in
            LetterToken(id: UUID(), letter: String(character).lowercased())
        }
        let wordLetterIDs = wordTokens.map(\.id)

        var bag = wordTokens
        let targetCount = word.count + numPaddingLetters
        while bag.count < targetCount {
            let index = Int.random(in: 0..<Self.alphabet.count, using: &rng)
            bag.append(LetterToken(id: UUID(), letter: Self.alphabet[index]))
        }
        bag.shuffle(using: &rng)
        return (bag, wordLetterIDs)
    }
}
