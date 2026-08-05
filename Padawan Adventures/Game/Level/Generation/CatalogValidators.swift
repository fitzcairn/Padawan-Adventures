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
                  !entry.sfx.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !entry.graphemes.isEmpty,
                  entry.graphemes.joined() == entry.word else {
                throw invalidEntryError
            }
            for grapheme in entry.graphemes {
                guard !grapheme.isEmpty,
                      grapheme.unicodeScalars.allSatisfy({ letterSet.contains($0) }) else {
                    throw invalidEntryError
                }
            }
        }
    }

    static func validateGraphemeEntries(
        _ graphemes: [GateGrapheme],
        requirePronunciation: Bool,
        emptyError: WorldSeedError,
        invalidEntryError: WorldSeedError
    ) throws {
        guard !graphemes.isEmpty else {
            throw emptyError
        }
        let letterSet = CharacterSet.letters
        var seen = Set<String>()
        for entry in graphemes {
            guard !entry.grapheme.isEmpty,
                  entry.grapheme.unicodeScalars.allSatisfy({ letterSet.contains($0) }),
                  !entry.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  seen.insert(entry.grapheme).inserted else {
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
