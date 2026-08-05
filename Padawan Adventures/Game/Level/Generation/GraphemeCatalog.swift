import Foundation
import Yams

/// YAML shape for one shared grapheme entry under `graphemes.<letter>:`.
/// `sfx` is the pronunciation track; `name` is the letter-name track.
nonisolated struct GraphemeSpec: Decodable, Equatable, Sendable {
    var sfx: String?
    var name: String?
}

/// Shared grapheme FX loaded from `Resources/Config/Catalogs/graphemes.yaml` for reuse across minigames.
nonisolated struct GraphemeCatalog: Equatable, Sendable {
    static let subdirectory = ConfigPath.catalogRoot

    /// Sorted by letter for deterministic iteration / RNG.
    private(set) var graphemes: [GateGrapheme]

    nonisolated static let fallback = GraphemeCatalog(graphemes: [
        .init(grapheme: "a", pronunciation: "sfx_grapheme_a_pronunciation", name: "sfx_grapheme_a_name"),
        .init(grapheme: "b", pronunciation: "sfx_grapheme_b_pronunciation", name: "sfx_grapheme_b_name"),
        .init(grapheme: "c", pronunciation: "sfx_grapheme_c_pronunciation", name: "sfx_grapheme_c_name"),
        .init(grapheme: "d", pronunciation: "sfx_grapheme_d_pronunciation", name: "sfx_grapheme_d_name"),
        .init(grapheme: "e", pronunciation: "sfx_grapheme_e_pronunciation", name: "sfx_grapheme_e_name"),
        .init(grapheme: "f", pronunciation: "sfx_grapheme_f_pronunciation", name: "sfx_grapheme_f_name"),
        .init(grapheme: "g", pronunciation: "sfx_grapheme_g_pronunciation", name: "sfx_grapheme_g_name"),
        .init(grapheme: "h", pronunciation: "sfx_grapheme_h_pronunciation", name: "sfx_grapheme_h_name"),
        .init(grapheme: "i", pronunciation: "sfx_grapheme_i_pronunciation", name: "sfx_grapheme_i_name"),
        .init(grapheme: "j", pronunciation: "sfx_grapheme_j_pronunciation", name: "sfx_grapheme_j_name"),
        .init(grapheme: "k", pronunciation: "sfx_grapheme_k_pronunciation", name: "sfx_grapheme_k_name"),
        .init(grapheme: "l", pronunciation: "sfx_grapheme_l_pronunciation", name: "sfx_grapheme_l_name"),
        .init(grapheme: "m", pronunciation: "sfx_grapheme_m_pronunciation", name: "sfx_grapheme_m_name"),
        .init(grapheme: "n", pronunciation: "sfx_grapheme_n_pronunciation", name: "sfx_grapheme_n_name"),
        .init(grapheme: "o", pronunciation: "sfx_grapheme_o_pronunciation", name: "sfx_grapheme_o_name"),
        .init(grapheme: "p", pronunciation: "sfx_grapheme_p_pronunciation", name: "sfx_grapheme_p_name"),
        .init(grapheme: "q", pronunciation: "sfx_grapheme_q_pronunciation", name: "sfx_grapheme_q_name"),
        .init(grapheme: "r", pronunciation: "sfx_grapheme_r_pronunciation", name: "sfx_grapheme_r_name"),
        .init(grapheme: "s", pronunciation: "sfx_grapheme_s_pronunciation", name: "sfx_grapheme_s_name"),
        .init(grapheme: "t", pronunciation: "sfx_grapheme_t_pronunciation", name: "sfx_grapheme_t_name"),
        .init(grapheme: "u", pronunciation: "sfx_grapheme_u_pronunciation", name: "sfx_grapheme_u_name"),
        .init(grapheme: "v", pronunciation: "sfx_grapheme_v_pronunciation", name: "sfx_grapheme_v_name"),
        .init(grapheme: "w", pronunciation: "sfx_grapheme_w_pronunciation", name: "sfx_grapheme_w_name"),
        .init(grapheme: "x", pronunciation: "sfx_grapheme_x_pronunciation", name: "sfx_grapheme_x_name"),
        .init(grapheme: "y", pronunciation: "sfx_grapheme_y_pronunciation", name: "sfx_grapheme_y_name"),
        .init(grapheme: "z", pronunciation: "sfx_grapheme_z_pronunciation", name: "sfx_grapheme_z_name"),
    ])

    nonisolated init(graphemes: [GateGrapheme]) {
        self.graphemes = GateGraphemeMatchConfig.normalizedGraphemes(graphemes)
    }

    func grapheme(named id: String) -> GateGrapheme? {
        let key = id.lowercased()
        return graphemes.first { $0.grapheme == key }
    }

    /// Resolves `ids` against the catalog. `nil` means the full catalog; `[]` is invalid.
    func resolve(ids: [String]?) throws -> [GateGrapheme] {
        guard let ids else {
            guard !graphemes.isEmpty else { throw WorldSeedError.invalidGateGraphemeMatchGraphemes }
            return graphemes
        }
        guard !ids.isEmpty else {
            throw WorldSeedError.invalidGateGraphemeMatchGraphemes
        }
        var resolved: [GateGrapheme] = []
        resolved.reserveCapacity(ids.count)
        for id in ids {
            guard let entry = grapheme(named: id) else {
                throw WorldSeedError.invalidGateGraphemeMatchGraphemes
            }
            resolved.append(entry)
        }
        return GateGraphemeMatchConfig.normalizedGraphemes(resolved)
    }

    func validate() throws {
        try CatalogValidators.validateGraphemeEntries(
            graphemes,
            requirePronunciation: true,
            emptyError: .invalidGateGraphemeMatchGraphemes,
            invalidEntryError: .invalidGateGraphemeMatchGraphemes
        )
    }

    static func loadFromBundle(
        named name: String = "graphemes",
        withExtension ext: String = "yaml",
        subdirectory: String? = subdirectory
    ) throws -> GraphemeCatalog {
        let data = try ConfigStore.data(
            at: ConfigPath(basename: name, subdirectory: subdirectory)
        )
        return try decode(from: data)
    }

    static func decode(from data: Data) throws -> GraphemeCatalog {
        do {
            let decoded = try YAMLDecoder().decode(GraphemeCatalogDTO.self, from: data)
            var resolved: [GateGrapheme] = []
            resolved.reserveCapacity(decoded.graphemes.count)
            for (key, spec) in decoded.graphemes {
                guard let entry = resolveEntry(id: key, spec: spec) else {
                    throw WorldSeedError.invalidGateGraphemeMatchGraphemes
                }
                resolved.append(entry)
            }
            let catalog = GraphemeCatalog(graphemes: resolved)
            try catalog.validate()
            return catalog
        } catch let error as WorldSeedError {
            throw error
        } catch {
            throw WorldSeedError.decodeFailed(String(describing: error))
        }
    }

    static func decode(from yaml: String) throws -> GraphemeCatalog {
        try decode(from: Data(yaml.utf8))
    }

    /// Requires explicit `sfx` (pronunciation) and `name` track basenames in YAML.
    nonisolated static func resolveEntry(id: String, spec: GraphemeSpec?) -> GateGrapheme? {
        guard let spec,
              let pronunciation = trimmedNonEmpty(spec.sfx),
              let name = trimmedNonEmpty(spec.name) else {
            return nil
        }

        return GateGrapheme(
            grapheme: id,
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

private nonisolated struct GraphemeCatalogDTO: Decodable {
    var graphemes: [String: GraphemeSpec?]
}
