import Foundation
import Yams

/// YAML shape for one shared vocabulary entry under `words.<word>:`.
/// Absent fields are derived from `fx_prefix` + the word id.
nonisolated struct WordSpec: Decodable, Equatable, Sendable {
    var spelling: String?
    var progressive: [String: String]?
}

/// Shared vocabulary + word FX loaded from `Resources/Config/Catalogs/words.yaml` for reuse across minigames.
nonisolated struct WordCatalog: Equatable, Sendable {
    static let subdirectory = ConfigPath.catalogRoot
    static let defaultFxPrefix = "sfx_word_"

    /// Sorted by word for deterministic iteration / RNG.
    private(set) var words: [GateWord]

    nonisolated static let fallback = WordCatalog(words: [
        .fallbackEntry(word: "cat"),
        .fallbackEntry(word: "dog"),
        .fallbackEntry(word: "gate"),
        .fallbackEntry(word: "open"),
        .fallbackEntry(word: "star"),
    ])

    nonisolated init(words: [GateWord]) {
        self.words = GateSpellingConfig.normalizedWords(words)
    }

    func word(named id: String) -> GateWord? {
        let key = id.lowercased()
        return words.first { $0.word == key }
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
            let fxPrefix = decoded.fxPrefix?.trimmingCharacters(in: .whitespacesAndNewlines)
            let prefix = (fxPrefix?.isEmpty == false) ? fxPrefix! : defaultFxPrefix
            let catalog = WordCatalog(
                words: decoded.words.map { key, spec in
                    resolveEntry(id: key, spec: spec, fxPrefix: prefix)
                }
            )
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

    /// Derives tracks from convention; explicit `spelling` / `progressive` keys override.
    nonisolated static func resolveEntry(id: String, spec: WordSpec?, fxPrefix: String) -> GateWord {
        let derived = GateWord.fallbackEntry(word: id, fxPrefix: fxPrefix)
        guard let spec else { return derived }

        let spelling: String
        if let override = spec.spelling?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            spelling = override
        } else {
            spelling = derived.spelling
        }

        var progressive = derived.progressive
        if let overrides = spec.progressive {
            for (key, value) in overrides {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                progressive[key.lowercased()] = trimmed
            }
        }

        return GateWord(word: id, spelling: spelling, progressive: progressive)
    }
}

private nonisolated struct WordCatalogDTO: Decodable {
    var fxPrefix: String?
    var words: [String: WordSpec?]

    enum CodingKeys: String, CodingKey {
        case fxPrefix = "fx_prefix"
        case words
    }
}
