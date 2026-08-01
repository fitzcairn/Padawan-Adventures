import Foundation

/// Shared word/letter validation for catalogs and minigame configs.
nonisolated enum CatalogValidators {
    static func validateWordEntries(
        _ words: [GateWord],
        emptyError: WorldSeedError,
        invalidEntryError: WorldSeedError
    ) throws {
        guard !words.isEmpty else {
            throw emptyError
        }
        let letterSet = CharacterSet.letters
        for entry in words {
            guard !entry.word.isEmpty,
                  entry.word.unicodeScalars.allSatisfy({ letterSet.contains($0) }),
                  !entry.spelling.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw invalidEntryError
            }
            var prefix = ""
            for character in entry.word {
                prefix.append(character)
                guard let track = entry.progressive[prefix]?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !track.isEmpty else {
                    throw invalidEntryError
                }
            }
        }
    }

    static func validateLetterEntries(
        _ letters: [GateLetter],
        requirePronunciation: Bool,
        emptyError: WorldSeedError,
        invalidEntryError: WorldSeedError
    ) throws {
        guard !letters.isEmpty else {
            throw emptyError
        }
        let letterSet = CharacterSet.letters
        var seen = Set<String>()
        for entry in letters {
            guard entry.letter.count == 1,
                  entry.letter.unicodeScalars.allSatisfy({ letterSet.contains($0) }),
                  !entry.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  seen.insert(entry.letter).inserted else {
                throw invalidEntryError
            }
            if requirePronunciation {
                guard !entry.pronunciation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw invalidEntryError
                }
            }
        }
    }
}
