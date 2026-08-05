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

    /// Mirrors `words.yaml`: most entries ship a `Sprites/Words/<word>.png`; `gate` is audio-only.
    nonisolated static let fallback = WordCatalog(words: [
        imagedFallbackEntry(word: "apple"),
        imagedFallbackEntry(word: "bath"),
        imagedFallbackEntry(word: "boat"),
        imagedFallbackEntry(word: "book"),
        imagedFallbackEntry(word: "car"),
        imagedFallbackEntry(word: "cat"),
        imagedFallbackEntry(word: "cloud"),
        imagedFallbackEntry(word: "dance"),
        imagedFallbackEntry(word: "dog"),
        .fallbackEntry(word: "gate"),
        imagedFallbackEntry(word: "house"),
        imagedFallbackEntry(word: "lightbulb"),
        imagedFallbackEntry(word: "pencil"),
        imagedFallbackEntry(word: "star"),
        imagedFallbackEntry(word: "sun"),
        imagedFallbackEntry(word: "trash"),
        imagedFallbackEntry(word: "wand"),
    ])

    /// Derived graphemes plus a sprite basename matching the word id.
    nonisolated static func imagedFallbackEntry(word: String) -> GateWord {
        let derived = GateWord.fallbackEntry(word: word)
        return GateWord(
            word: derived.word,
            image: derived.word,
            sfx: derived.sfx,
            graphemes: derived.graphemes
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
