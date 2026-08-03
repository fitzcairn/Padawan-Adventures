import Foundation
import Yams

/// YAML shape for one shared phonics entry under `phonics.<letter>:`.
/// `sfx` is the pronunciation track; `name` is the letter-name track.
nonisolated struct LetterSpec: Decodable, Equatable, Sendable {
    var sfx: String?
    var name: String?
}

/// Shared phonics FX loaded from `Resources/Config/Catalogs/phonics.yaml` for reuse across minigames.
nonisolated struct LetterCatalog: Equatable, Sendable {
    static let subdirectory = ConfigPath.catalogRoot

    /// Sorted by letter for deterministic iteration / RNG.
    private(set) var letters: [GateLetter]

    nonisolated static let fallback = LetterCatalog(letters: [
        .init(letter: "a", pronunciation: "sfx_letter_a_pronunciation", name: "sfx_letter_a_name"),
        .init(letter: "b", pronunciation: "sfx_letter_b_pronunciation", name: "sfx_letter_b_name"),
        .init(letter: "c", pronunciation: "sfx_letter_c_pronunciation", name: "sfx_letter_c_name"),
        .init(letter: "d", pronunciation: "sfx_letter_d_pronunciation", name: "sfx_letter_d_name"),
        .init(letter: "e", pronunciation: "sfx_letter_e_pronunciation", name: "sfx_letter_e_name"),
        .init(letter: "f", pronunciation: "sfx_letter_f_pronunciation", name: "sfx_letter_f_name"),
        .init(letter: "g", pronunciation: "sfx_letter_g_pronunciation", name: "sfx_letter_g_name"),
        .init(letter: "h", pronunciation: "sfx_letter_h_pronunciation", name: "sfx_letter_h_name"),
        .init(letter: "l", pronunciation: "sfx_letter_l_pronunciation", name: "sfx_letter_l_name"),
        .init(letter: "m", pronunciation: "sfx_letter_m_pronunciation", name: "sfx_letter_m_name"),
        .init(letter: "o", pronunciation: "sfx_letter_o_pronunciation", name: "sfx_letter_o_name"),
        .init(letter: "p", pronunciation: "sfx_letter_p_pronunciation", name: "sfx_letter_p_name"),
        .init(letter: "s", pronunciation: "sfx_letter_s_pronunciation", name: "sfx_letter_s_name"),
        .init(letter: "w", pronunciation: "sfx_letter_w_pronunciation", name: "sfx_letter_w_name"),
    ])

    nonisolated init(letters: [GateLetter]) {
        self.letters = GateLetterMatchConfig.normalizedLetters(letters)
    }

    func letter(named id: String) -> GateLetter? {
        let key = id.lowercased()
        return letters.first { $0.letter == key }
    }

    /// Resolves `ids` against the catalog. `nil` means the full catalog; `[]` is invalid.
    func resolve(ids: [String]?) throws -> [GateLetter] {
        guard let ids else {
            guard !letters.isEmpty else { throw WorldSeedError.invalidGateLetterMatchLetters }
            return letters
        }
        guard !ids.isEmpty else {
            throw WorldSeedError.invalidGateLetterMatchLetters
        }
        var resolved: [GateLetter] = []
        resolved.reserveCapacity(ids.count)
        for id in ids {
            guard let entry = letter(named: id) else {
                throw WorldSeedError.invalidGateLetterMatchLetters
            }
            resolved.append(entry)
        }
        return GateLetterMatchConfig.normalizedLetters(resolved)
    }

    func validate() throws {
        try CatalogValidators.validateLetterEntries(
            letters,
            requirePronunciation: true,
            emptyError: .invalidGateLetterMatchLetters,
            invalidEntryError: .invalidGateLetterMatchLetters
        )
    }

    static func loadFromBundle(
        named name: String = "phonics",
        withExtension ext: String = "yaml",
        subdirectory: String? = subdirectory
    ) throws -> LetterCatalog {
        let data = try ConfigStore.data(
            at: ConfigPath(basename: name, subdirectory: subdirectory)
        )
        return try decode(from: data)
    }

    static func decode(from data: Data) throws -> LetterCatalog {
        do {
            let decoded = try YAMLDecoder().decode(LetterCatalogDTO.self, from: data)
            var resolved: [GateLetter] = []
            resolved.reserveCapacity(decoded.phonics.count)
            for (key, spec) in decoded.phonics {
                guard let entry = resolveEntry(id: key, spec: spec) else {
                    throw WorldSeedError.invalidGateLetterMatchLetters
                }
                resolved.append(entry)
            }
            let catalog = LetterCatalog(letters: resolved)
            try catalog.validate()
            return catalog
        } catch let error as WorldSeedError {
            throw error
        } catch {
            throw WorldSeedError.decodeFailed(String(describing: error))
        }
    }

    static func decode(from yaml: String) throws -> LetterCatalog {
        try decode(from: Data(yaml.utf8))
    }

    /// Requires explicit `sfx` (pronunciation) and `name` track basenames in YAML.
    nonisolated static func resolveEntry(id: String, spec: LetterSpec?) -> GateLetter? {
        guard let spec,
              let pronunciation = trimmedNonEmpty(spec.sfx),
              let name = trimmedNonEmpty(spec.name) else {
            return nil
        }

        return GateLetter(
            letter: id,
            pronunciation: pronunciation,
            name: name
        )
    }

    private nonisolated static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private nonisolated struct LetterCatalogDTO: Decodable {
    var phonics: [String: LetterSpec?]
}
