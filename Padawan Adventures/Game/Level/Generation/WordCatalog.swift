import Foundation
import Yams

/// YAML shape for one shared vocabulary entry under `words.<word>:`.
nonisolated struct WordSpec: Decodable, Equatable, Sendable {
    var spelling: String
    var progressive: [String: String]
}

/// Shared vocabulary + word FX loaded from `Resources/Config/Vocab/words.yaml` for reuse across minigames.
nonisolated struct WordCatalog: Equatable, Sendable {
    static let subdirectory = "Vocab"

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
        self.words = GatePuzzleConfig.normalizedWords(words)
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
        return GatePuzzleConfig.normalizedWords(resolved)
    }

    func validate() throws {
        guard !words.isEmpty else {
            throw WorldSeedError.invalidGateWords
        }
        let letterSet = CharacterSet.letters
        for entry in words {
            guard !entry.word.isEmpty,
                  entry.word.unicodeScalars.allSatisfy({ letterSet.contains($0) }),
                  !entry.spelling.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw WorldSeedError.invalidGateWords
            }
            var prefix = ""
            for character in entry.word {
                prefix.append(character)
                guard let track = entry.progressive[prefix]?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !track.isEmpty else {
                    throw WorldSeedError.invalidGateWords
                }
            }
        }
    }

    static func loadFromBundle(
        named name: String = "words",
        withExtension ext: String = "yaml",
        subdirectory: String? = subdirectory
    ) throws -> WordCatalog {
        // Prefer Vocab/; fall back to bundle root if Xcode flattens the resource.
        if let subdirectory,
           let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdirectory) {
            return try decode(from: Data(contentsOf: url))
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            throw WorldSeedError.missingResource
        }
        return try decode(from: Data(contentsOf: url))
    }

    static func decode(from data: Data) throws -> WordCatalog {
        do {
            let decoded = try YAMLDecoder().decode(WordCatalogDTO.self, from: data)
            let catalog = WordCatalog(
                words: decoded.words.map { key, spec in
                    GateWord(word: key, spelling: spec.spelling, progressive: spec.progressive)
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
}

private struct WordCatalogDTO: Decodable {
    var words: [String: WordSpec]
}
