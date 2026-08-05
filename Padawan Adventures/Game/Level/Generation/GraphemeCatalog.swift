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
        .init(grapheme: "a", pronunciation: "sfx_letter_a_pronunciation", name: "sfx_letter_a_name"),
        .init(grapheme: "b", pronunciation: "sfx_letter_b_pronunciation", name: "sfx_letter_b_name"),
        .init(grapheme: "c", pronunciation: "sfx_letter_c_pronunciation", name: "sfx_letter_c_name"),
        .init(grapheme: "d", pronunciation: "sfx_letter_d_pronunciation", name: "sfx_letter_d_name"),
        .init(grapheme: "e", pronunciation: "sfx_letter_e_pronunciation", name: "sfx_letter_e_name"),
        .init(grapheme: "f", pronunciation: "sfx_letter_f_pronunciation", name: "sfx_letter_f_name"),
        .init(grapheme: "g", pronunciation: "sfx_letter_g_pronunciation", name: "sfx_letter_g_name"),
        .init(grapheme: "h", pronunciation: "sfx_letter_h_pronunciation", name: "sfx_letter_h_name"),
        .init(grapheme: "i", pronunciation: "sfx_letter_i_pronunciation", name: "sfx_letter_i_name"),
        .init(grapheme: "j", pronunciation: "sfx_letter_j_pronunciation", name: "sfx_letter_j_name"),
        .init(grapheme: "k", pronunciation: "sfx_letter_k_pronunciation", name: "sfx_letter_k_name"),
        .init(grapheme: "l", pronunciation: "sfx_letter_l_pronunciation", name: "sfx_letter_l_name"),
        .init(grapheme: "m", pronunciation: "sfx_letter_m_pronunciation", name: "sfx_letter_m_name"),
        .init(grapheme: "n", pronunciation: "sfx_letter_n_pronunciation", name: "sfx_letter_n_name"),
        .init(grapheme: "o", pronunciation: "sfx_letter_o_pronunciation", name: "sfx_letter_o_name"),
        .init(grapheme: "p", pronunciation: "sfx_letter_p_pronunciation", name: "sfx_letter_p_name"),
        .init(grapheme: "q", pronunciation: "sfx_letter_q_pronunciation", name: "sfx_letter_q_name"),
        .init(grapheme: "r", pronunciation: "sfx_letter_r_pronunciation", name: "sfx_letter_r_name"),
        .init(grapheme: "s", pronunciation: "sfx_letter_s_pronunciation", name: "sfx_letter_s_name"),
        .init(grapheme: "t", pronunciation: "sfx_letter_t_pronunciation", name: "sfx_letter_t_name"),
        .init(grapheme: "u", pronunciation: "sfx_letter_u_pronunciation", name: "sfx_letter_u_name"),
        .init(grapheme: "v", pronunciation: "sfx_letter_v_pronunciation", name: "sfx_letter_v_name"),
        .init(grapheme: "w", pronunciation: "sfx_letter_w_pronunciation", name: "sfx_letter_w_name"),
        .init(grapheme: "x", pronunciation: "sfx_letter_x_pronunciation", name: "sfx_letter_x_name"),
        .init(grapheme: "y", pronunciation: "sfx_letter_y_pronunciation", name: "sfx_letter_y_name"),
        .init(grapheme: "z", pronunciation: "sfx_letter_z_pronunciation", name: "sfx_letter_z_name"),
        .init(grapheme: "ai", pronunciation: "sfx_grapheme_ai_pronunciation", name: "sfx_grapheme_ai_name"),
        .init(grapheme: "ay", pronunciation: "sfx_grapheme_ay_pronunciation", name: "sfx_grapheme_ay_name"),
        .init(grapheme: "bl", pronunciation: "sfx_grapheme_bl_pronunciation", name: "sfx_grapheme_bl_name"),
        .init(grapheme: "br", pronunciation: "sfx_grapheme_br_pronunciation", name: "sfx_grapheme_br_name"),
        .init(grapheme: "cr", pronunciation: "sfx_grapheme_cr_pronunciation", name: "sfx_grapheme_cr_name"),
        .init(grapheme: "ea", pronunciation: "sfx_grapheme_ea_pronunciation", name: "sfx_grapheme_ea_name"),
        .init(grapheme: "ee", pronunciation: "sfx_grapheme_ee_pronunciation", name: "sfx_grapheme_ee_name"),
        .init(grapheme: "ff", pronunciation: "sfx_grapheme_ff_pronunciation", name: "sfx_grapheme_ff_name"),
        .init(grapheme: "fl", pronunciation: "sfx_grapheme_fl_pronunciation", name: "sfx_grapheme_fl_name"),
        .init(grapheme: "fr", pronunciation: "sfx_grapheme_fr_pronunciation", name: "sfx_grapheme_fr_name"),
        .init(grapheme: "igh", pronunciation: "sfx_grapheme_igh_pronunciation", name: "sfx_grapheme_igh_name"),
        .init(grapheme: "ll", pronunciation: "sfx_grapheme_ll_pronunciation", name: "sfx_grapheme_ll_name"),
        .init(grapheme: "mp", pronunciation: "sfx_grapheme_mp_pronunciation", name: "sfx_grapheme_mp_name"),
        .init(grapheme: "nd", pronunciation: "sfx_grapheme_nd_pronunciation", name: "sfx_grapheme_nd_name"),
        .init(grapheme: "nt", pronunciation: "sfx_grapheme_nt_pronunciation", name: "sfx_grapheme_nt_name"),
        .init(grapheme: "oa", pronunciation: "sfx_grapheme_oa_pronunciation", name: "sfx_grapheme_oa_name"),
        .init(grapheme: "ow", pronunciation: "sfx_grapheme_ow_pronunciation", name: "sfx_grapheme_ow_name"),
        .init(grapheme: "pl", pronunciation: "sfx_grapheme_pl_pronunciation", name: "sfx_grapheme_pl_name"),
        .init(grapheme: "qu", pronunciation: "sfx_grapheme_qu_pronunciation", name: "sfx_grapheme_qu_name"),
        .init(grapheme: "sh", pronunciation: "sfx_grapheme_sh_pronunciation", name: "sfx_grapheme_sh_name"),
        .init(grapheme: "sl", pronunciation: "sfx_grapheme_sl_pronunciation", name: "sfx_grapheme_sl_name"),
        .init(grapheme: "sn", pronunciation: "sfx_grapheme_sn_pronunciation", name: "sfx_grapheme_sn_name"),
        .init(grapheme: "sp", pronunciation: "sfx_grapheme_sp_pronunciation", name: "sfx_grapheme_sp_name"),
        .init(grapheme: "ss", pronunciation: "sfx_grapheme_ss_pronunciation", name: "sfx_grapheme_ss_name"),
        .init(grapheme: "st", pronunciation: "sfx_grapheme_st_pronunciation", name: "sfx_grapheme_st_name"),
        .init(grapheme: "tr", pronunciation: "sfx_grapheme_tr_pronunciation", name: "sfx_grapheme_tr_name"),
        .init(grapheme: "zz", pronunciation: "sfx_grapheme_zz_pronunciation", name: "sfx_grapheme_zz_name"),
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
