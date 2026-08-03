import Foundation
import Yams

/// YAML shape for one shared vocabulary entry under `words.<word>:`.
/// `sfx` is required; progressive prefixes default to `<sfx>_<prefix>` when omitted.
nonisolated struct WordSpec: Decodable, Equatable, Sendable {
    var image: String?
    var sfx: String?
    var progressive: [String: String]?
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

    /// Derived tracks plus a sprite basename matching the word id.
    nonisolated static func imagedFallbackEntry(word: String) -> GateWord {
        let derived = GateWord.fallbackEntry(word: word)
        return GateWord(
            word: derived.word,
            image: derived.word,
            sfx: derived.sfx,
            progressive: derived.progressive
        )
    }

    nonisolated init(words: [GateWord]) {
        self.words = GateSpellingConfig.normalizedWords(words)
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
        return GateSpellingConfig.normalizedWords(resolved)
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

    /// Requires explicit `sfx`. Progressive prefixes default to `<sfx>_<prefix>`;
    /// explicit `progressive` / `image` keys override.
    nonisolated static func resolveEntry(id: String, spec: WordSpec?) -> GateWord? {
        guard let spec,
              let sfx = trimmedNonEmpty(spec.sfx) else {
            return nil
        }

        let derived = GateWord.fallbackEntry(word: id, sfx: sfx)
        let image = trimmedNonEmpty(spec.image)

        var progressive = derived.progressive
        if let overrides = spec.progressive {
            for (key, value) in overrides {
                guard let trimmed = trimmedNonEmpty(value) else { continue }
                progressive[key.lowercased()] = trimmed
            }
        }

        return GateWord(word: id, image: image, sfx: sfx, progressive: progressive)
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
