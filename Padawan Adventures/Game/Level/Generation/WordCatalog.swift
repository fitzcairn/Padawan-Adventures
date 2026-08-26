import Foundation
import Yams

/// YAML shape for one shared vocabulary entry under `words.<word>:`.
/// `sfx` and `graphemes` are required; `graphemes` must concatenate to the word id.
nonisolated struct WordSpec: Decodable, Equatable, Sendable {
    var image: String?
    var sfx: String?
    var graphemes: [String]?
}

/// Shared vocabulary + word FX loaded from `Resources/Config/Catalogs/words.yaml` for reuse across minigames.
nonisolated struct WordCatalog: Equatable, Sendable {
    static let subdirectory = ConfigPath.catalogRoot
    static let imageRoot = "Sprites/Words"

    /// Sorted by word for deterministic iteration / RNG.
    private(set) var words: [GateWord]

    /// Mirrors `words.yaml` curriculum entries (imaged).
    nonisolated static let fallback = WordCatalog(words: [
        imagedFallbackEntry(word: "an", graphemes: ["a", "n"]),
        imagedFallbackEntry(word: "ant", graphemes: ["a", "nt"]),
        imagedFallbackEntry(word: "at", graphemes: ["a", "t"]),
        imagedFallbackEntry(word: "bat", graphemes: ["b", "a", "t"]),
        imagedFallbackEntry(word: "bed", graphemes: ["b", "e", "d"]),
        imagedFallbackEntry(word: "blow", graphemes: ["bl", "ow"]),
        imagedFallbackEntry(word: "boat", graphemes: ["b", "oa", "t"]),
        imagedFallbackEntry(word: "brush", graphemes: ["br", "u", "sh"]),
        imagedFallbackEntry(word: "bug", graphemes: ["b", "u", "g"]),
        imagedFallbackEntry(word: "bus", graphemes: ["b", "u", "s"]),
        imagedFallbackEntry(word: "buzz", graphemes: ["b", "u", "zz"]),
        imagedFallbackEntry(word: "camp", graphemes: ["c", "a", "mp"]),
        imagedFallbackEntry(word: "can", graphemes: ["c", "a", "n"]),
        imagedFallbackEntry(word: "cap", graphemes: ["c", "a", "p"]),
        imagedFallbackEntry(word: "cat", graphemes: ["c", "a", "t"]),
        imagedFallbackEntry(word: "coat", graphemes: ["c", "oa", "t"]),
        imagedFallbackEntry(word: "crab", graphemes: ["cr", "a", "b"]),
        imagedFallbackEntry(word: "cup", graphemes: ["c", "u", "p"]),
        imagedFallbackEntry(word: "dad", graphemes: ["d", "a", "d"]),
        imagedFallbackEntry(word: "day", graphemes: ["d", "ay"]),
        imagedFallbackEntry(word: "dig", graphemes: ["d", "i", "g"]),
        imagedFallbackEntry(word: "dog", graphemes: ["d", "o", "g"]),
        imagedFallbackEntry(word: "fast", graphemes: ["f", "a", "st"]),
        imagedFallbackEntry(word: "flag", graphemes: ["fl", "a", "g"]),
        imagedFallbackEntry(word: "fox", graphemes: ["f", "o", "x"]),
        imagedFallbackEntry(word: "frog", graphemes: ["fr", "o", "g"]),
        imagedFallbackEntry(word: "hat", graphemes: ["h", "a", "t"]),
        imagedFallbackEntry(word: "high", graphemes: ["h", "igh"]),
        imagedFallbackEntry(word: "hill", graphemes: ["h", "i", "ll"]),
        imagedFallbackEntry(word: "in", graphemes: ["i", "n"]),
        imagedFallbackEntry(word: "it", graphemes: ["i", "t"]),
        imagedFallbackEntry(word: "jam", graphemes: ["j", "a", "m"]),
        imagedFallbackEntry(word: "jog", graphemes: ["j", "o", "g"]),
        imagedFallbackEntry(word: "jump", graphemes: ["j", "u", "mp"]),
        imagedFallbackEntry(word: "kam", graphemes: ["k", "a", "m"]),
        imagedFallbackEntry(word: "kid", graphemes: ["k", "i", "d"]),
        imagedFallbackEntry(word: "kiss", graphemes: ["k", "i", "ss"]),
        imagedFallbackEntry(word: "mad", graphemes: ["m", "a", "d"]),
        imagedFallbackEntry(word: "map", graphemes: ["m", "a", "p"]),
        imagedFallbackEntry(word: "mat", graphemes: ["m", "a", "t"]),
        imagedFallbackEntry(word: "mop", graphemes: ["m", "o", "p"]),
        imagedFallbackEntry(word: "nap", graphemes: ["n", "a", "p"]),
        imagedFallbackEntry(word: "nest", graphemes: ["n", "e", "st"]),
        imagedFallbackEntry(word: "night", graphemes: ["n", "igh", "t"]),
        imagedFallbackEntry(word: "padawan", graphemes: ["p", "a", "d", "a", "w", "a", "n"]),
        imagedFallbackEntry(word: "pan", graphemes: ["p", "a", "n"]),
        imagedFallbackEntry(word: "pat", graphemes: ["p", "a", "t"]),
        imagedFallbackEntry(word: "pet", graphemes: ["p", "e", "t"]),
        imagedFallbackEntry(word: "pig", graphemes: ["p", "i", "g"]),
        imagedFallbackEntry(word: "pin", graphemes: ["p", "i", "n"]),
        imagedFallbackEntry(word: "pit", graphemes: ["p", "i", "t"]),
        imagedFallbackEntry(word: "play", graphemes: ["pl", "ay"]),
        imagedFallbackEntry(word: "plum", graphemes: ["pl", "u", "m"]),
        imagedFallbackEntry(word: "pond", graphemes: ["p", "o", "nd"]),
        imagedFallbackEntry(word: "pop", graphemes: ["p", "o", "p"]),
        imagedFallbackEntry(word: "pot", graphemes: ["p", "o", "t"]),
        imagedFallbackEntry(word: "puff", graphemes: ["p", "u", "ff"]),
        imagedFallbackEntry(word: "quit", graphemes: ["qu", "i", "t"]),
        imagedFallbackEntry(word: "quiz", graphemes: ["qu", "i", "z"]),
        imagedFallbackEntry(word: "rain", graphemes: ["r", "ai", "n"]),
        imagedFallbackEntry(word: "read", graphemes: ["r", "ea", "d"]),
        imagedFallbackEntry(word: "rug", graphemes: ["r", "u", "g"]),
        imagedFallbackEntry(word: "run", graphemes: ["r", "u", "n"]),
        imagedFallbackEntry(word: "sand", graphemes: ["s", "a", "nd"]),
        imagedFallbackEntry(word: "sap", graphemes: ["s", "a", "p"]),
        imagedFallbackEntry(word: "sat", graphemes: ["s", "a", "t"]),
        imagedFallbackEntry(word: "sea", graphemes: ["s", "ea"]),
        imagedFallbackEntry(word: "see", graphemes: ["s", "ee"]),
        imagedFallbackEntry(word: "sip", graphemes: ["s", "i", "p"]),
        imagedFallbackEntry(word: "sit", graphemes: ["s", "i", "t"]),
        imagedFallbackEntry(word: "slip", graphemes: ["sl", "i", "p"]),
        imagedFallbackEntry(word: "snap", graphemes: ["sn", "a", "p"]),
        imagedFallbackEntry(word: "snow", graphemes: ["sn", "ow"]),
        imagedFallbackEntry(word: "spot", graphemes: ["sp", "o", "t"]),
        imagedFallbackEntry(word: "stop", graphemes: ["st", "o", "p"]),
        imagedFallbackEntry(word: "sun", graphemes: ["s", "u", "n"]),
        imagedFallbackEntry(word: "tap", graphemes: ["t", "a", "p"]),
        imagedFallbackEntry(word: "tent", graphemes: ["t", "e", "nt"]),
        imagedFallbackEntry(word: "tip", graphemes: ["t", "i", "p"]),
        imagedFallbackEntry(word: "top", graphemes: ["t", "o", "p"]),
        imagedFallbackEntry(word: "train", graphemes: ["tr", "ai", "n"]),
        imagedFallbackEntry(word: "tree", graphemes: ["tr", "ee"]),
        imagedFallbackEntry(word: "tris", graphemes: ["tr", "i", "s"]),
        imagedFallbackEntry(word: "van", graphemes: ["v", "a", "n"]),
        imagedFallbackEntry(word: "vest", graphemes: ["v", "e", "st"]),
        imagedFallbackEntry(word: "vet", graphemes: ["v", "e", "t"]),
        imagedFallbackEntry(word: "web", graphemes: ["w", "e", "b"]),
        imagedFallbackEntry(word: "wig", graphemes: ["w", "i", "g"]),
        imagedFallbackEntry(word: "yes", graphemes: ["y", "e", "s"]),
        imagedFallbackEntry(word: "zip", graphemes: ["z", "i", "p"]),
    ])

    /// Sprite basename matching the word id, with optional explicit grapheme breakdown.
    nonisolated static func imagedFallbackEntry(
        word: String,
        graphemes: [String]? = nil
    ) -> GateWord {
        let derived = GateWord.fallbackEntry(word: word)
        return GateWord(
            word: derived.word,
            image: derived.word,
            sfx: derived.sfx,
            graphemes: graphemes ?? derived.graphemes
        )
    }

    nonisolated init(words: [GateWord]) {
        self.words = GateWord.normalized(words)
    }

    func word(named id: String) -> GateWord? {
        let key = id.lowercased()
        return words.first { $0.word == key }
    }

    /// Words whose spelling begins with `letter`. When `requiringImage` is true, only
    /// entries with a non-empty `image` basename are returned (usable as throw sprites).
    func words(startingWith letter: String, requiringImage: Bool = false) -> [GateWord] {
        let key = letter.lowercased()
        guard !key.isEmpty else { return [] }
        return words.filter { entry in
            guard entry.word.hasPrefix(key) else { return false }
            if requiringImage {
                guard let image = entry.image, !image.isEmpty else { return false }
            }
            return true
        }
    }

    /// Resolves `ids` against the catalog. `nil` means the full catalog; `[]` is invalid.
    func resolve(ids: [String]?) throws -> [GateWord] {
        guard let ids else {
            guard !words.isEmpty else { throw WorldSeedError.invalidGateWords }
            return words
        }
        guard !ids.isEmpty else {
            throw WorldSeedError.invalidGateWords
        }
        var resolved: [GateWord] = []
        resolved.reserveCapacity(ids.count)
        for id in ids {
            guard let entry = word(named: id) else {
                throw WorldSeedError.invalidGateWords
            }
            resolved.append(entry)
        }
        return GateWord.normalized(resolved)
    }

    func validate() throws {
        try CatalogValidators.validateWordEntries(
            words,
            emptyError: .invalidGateWords,
            invalidEntryError: .invalidGateWords
        )
    }

    static func loadFromBundle(
        named name: String = "words",
        withExtension ext: String = "yaml",
        subdirectory: String? = subdirectory
    ) throws -> WordCatalog {
        let data = try ConfigStore.data(
            at: ConfigPath(basename: name, subdirectory: subdirectory)
        )
        return try decode(from: data)
    }

    static func decode(from data: Data) throws -> WordCatalog {
        do {
            let decoded = try YAMLDecoder().decode(WordCatalogDTO.self, from: data)
            var resolved: [GateWord] = []
            resolved.reserveCapacity(decoded.words.count)
            for (key, spec) in decoded.words {
                guard let entry = resolveEntry(id: key, spec: spec) else {
                    throw WorldSeedError.invalidGateWords
                }
                resolved.append(entry)
            }
            let catalog = WordCatalog(words: resolved)
            try catalog.validate()
            return catalog
        } catch let error as WorldSeedError {
            throw error
        } catch {
            throw WorldSeedError.decodeFailed(String(describing: error))
        }
    }

    static func decode(from yaml: String) throws -> WordCatalog {
        try decode(from: Data(yaml.utf8))
    }

    /// Requires explicit `sfx` and a non-empty `graphemes` list that concatenates to `id`.
    nonisolated static func resolveEntry(id: String, spec: WordSpec?) -> GateWord? {
        guard let spec,
              let sfx = trimmedNonEmpty(spec.sfx),
              let rawGraphemes = spec.graphemes,
              !rawGraphemes.isEmpty else {
            return nil
        }

        let graphemes = rawGraphemes.compactMap { raw -> String? in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return trimmed.isEmpty ? nil : trimmed
        }
        guard !graphemes.isEmpty,
              graphemes.joined() == id.lowercased() else {
            return nil
        }

        let image = trimmedNonEmpty(spec.image)
        return GateWord(word: id, image: image, sfx: sfx, graphemes: graphemes)
    }

    private nonisolated static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private nonisolated struct WordCatalogDTO: Decodable {
    var words: [String: WordSpec?]
}
