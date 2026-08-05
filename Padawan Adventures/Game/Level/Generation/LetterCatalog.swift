import Foundation
import Yams

/// YAML shape for one shared grapheme entry under `graphemes.<letter>:`.
/// `sfx` is the pronunciation track; `name` is the letter-name track.
nonisolated struct LetterSpec: Decodable, Equatable, Sendable {
    var sfx: String?
    var name: String?
}

/// Shared grapheme FX loaded from `Resources/Config/Catalogs/graphemes.yaml` for reuse across minigames.
nonisolated struct LetterCatalog: Equatable, Sendable {
    static let subdirectory = ConfigPath.catalogRoot

    /// Sorted by letter for deterministic iteration / RNG.
    private(set) var letters: [GateLetter]

    nonisolated static let fallback = LetterCatalog(letters: [
        .init(letter: "a", pronunciation: "sfx_grapheme_a_pronunciation", name: "sfx_grapheme_a_name"),
        .init(letter: "b", pronunciation: "sfx_grapheme_b_pronunciation", name: "sfx_grapheme_b_name"),
        .init(letter: "c", pronunciation: "sfx_grapheme_c_pronunciation", name: "sfx_grapheme_c_name"),
        .init(letter: "d", pronunciation: "sfx_grapheme_d_pronunciation", name: "sfx_grapheme_d_name"),
        .init(letter: "e", pronunciation: "sfx_grapheme_e_pronunciation", name: "sfx_grapheme_e_name"),
        .init(letter: "f", pronunciation: "sfx_grapheme_f_pronunciation", name: "sfx_grapheme_f_name"),
        .init(letter: "g", pronunciation: "sfx_grapheme_g_pronunciation", name: "sfx_grapheme_g_name"),
        .init(letter: "h", pronunciation: "sfx_grapheme_h_pronunciation", name: "sfx_grapheme_h_name"),
        .init(letter: "i", pronunciation: "sfx_grapheme_i_pronunciation", name: "sfx_grapheme_i_name"),
        .init(letter: "j", pronunciation: "sfx_grapheme_j_pronunciation", name: "sfx_grapheme_j_name"),
        .init(letter: "k", pronunciation: "sfx_grapheme_k_pronunciation", name: "sfx_grapheme_k_name"),
        .init(letter: "l", pronunciation: "sfx_grapheme_l_pronunciation", name: "sfx_grapheme_l_name"),
        .init(letter: "m", pronunciation: "sfx_grapheme_m_pronunciation", name: "sfx_grapheme_m_name"),
        .init(letter: "n", pronunciation: "sfx_grapheme_n_pronunciation", name: "sfx_grapheme_n_name"),
        .init(letter: "o", pronunciation: "sfx_grapheme_o_pronunciation", name: "sfx_grapheme_o_name"),
        .init(letter: "p", pronunciation: "sfx_grapheme_p_pronunciation", name: "sfx_grapheme_p_name"),
        .init(letter: "q", pronunciation: "sfx_grapheme_q_pronunciation", name: "sfx_grapheme_q_name"),
        .init(letter: "r", pronunciation: "sfx_grapheme_r_pronunciation", name: "sfx_grapheme_r_name"),
        .init(letter: "s", pronunciation: "sfx_grapheme_s_pronunciation", name: "sfx_grapheme_s_name"),
        .init(letter: "t", pronunciation: "sfx_grapheme_t_pronunciation", name: "sfx_grapheme_t_name"),
        .init(letter: "u", pronunciation: "sfx_grapheme_u_pronunciation", name: "sfx_grapheme_u_name"),
        .init(letter: "v", pronunciation: "sfx_grapheme_v_pronunciation", name: "sfx_grapheme_v_name"),
        .init(letter: "w", pronunciation: "sfx_grapheme_w_pronunciation", name: "sfx_grapheme_w_name"),
        .init(letter: "x", pronunciation: "sfx_grapheme_x_pronunciation", name: "sfx_grapheme_x_name"),
        .init(letter: "y", pronunciation: "sfx_grapheme_y_pronunciation", name: "sfx_grapheme_y_name"),
        .init(letter: "z", pronunciation: "sfx_grapheme_z_pronunciation", name: "sfx_grapheme_z_name"),
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
        named name: String = "graphemes",
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
            resolved.reserveCapacity(decoded.graphemes.count)
            for (key, spec) in decoded.graphemes {
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
    var graphemes: [String: LetterSpec?]
}
