import Foundation
import Yams

/// YAML shape for one shared letter entry under `letters.<letter>:`.
/// Absent fields are derived via `LetterSoundCatalog`.
nonisolated struct LetterSpec: Decodable, Equatable, Sendable {
    var pronunciation: String?
    var name: String?
}

/// Shared letter FX loaded from `Resources/Config/Catalogs/letters.yaml` for reuse across minigames.
nonisolated struct LetterCatalog: Equatable, Sendable {
    static let subdirectory = "Catalogs"
    static let defaultFxPrefix = "sfx_letter_"

    /// Sorted by letter for deterministic iteration / RNG.
    private(set) var letters: [DestructibleWallLetter]

    nonisolated static let fallback = LetterCatalog(letters: [
        .init(letter: "a", pronunciation: "sfx_letter_a_pronunciation", name: "sfx_letter_a_name"),
        .init(letter: "b", pronunciation: "sfx_letter_b_pronunciation", name: "sfx_letter_b_name"),
        .init(letter: "c", pronunciation: "sfx_letter_c_pronunciation", name: "sfx_letter_c_name"),
        .init(letter: "d", pronunciation: "sfx_letter_d_pronunciation", name: "sfx_letter_d_name"),
        .init(letter: "e", pronunciation: "sfx_letter_e_pronunciation", name: "sfx_letter_e_name"),
        .init(letter: "f", pronunciation: "sfx_letter_f_pronunciation", name: "sfx_letter_f_name"),
        .init(letter: "g", pronunciation: "sfx_letter_g_pronunciation", name: "sfx_letter_g_name"),
        .init(letter: "h", pronunciation: "sfx_letter_h_pronunciation", name: "sfx_letter_h_name"),
    ])

    nonisolated init(letters: [DestructibleWallLetter]) {
        self.letters = DestructibleWallPuzzleConfig.normalizedLetters(letters)
    }

    func letter(named id: String) -> DestructibleWallLetter? {
        let key = id.lowercased()
        return letters.first { $0.letter == key }
    }

    /// Resolves `ids` against the catalog. `nil` means the full catalog; `[]` is invalid.
    func resolve(ids: [String]?) throws -> [DestructibleWallLetter] {
        guard let ids else {
            guard !letters.isEmpty else { throw WorldSeedError.invalidDestructibleWallLetters }
            return letters
        }
        guard !ids.isEmpty else {
            throw WorldSeedError.invalidDestructibleWallLetters
        }
        var resolved: [DestructibleWallLetter] = []
        resolved.reserveCapacity(ids.count)
        for id in ids {
            guard let entry = letter(named: id) else {
                throw WorldSeedError.invalidDestructibleWallLetters
            }
            resolved.append(entry)
        }
        return DestructibleWallPuzzleConfig.normalizedLetters(resolved)
    }

    func validate() throws {
        guard !letters.isEmpty else {
            throw WorldSeedError.invalidDestructibleWallLetters
        }
        let letterSet = CharacterSet.letters
        var seen = Set<String>()
        for entry in letters {
            guard entry.letter.count == 1,
                  entry.letter.unicodeScalars.allSatisfy({ letterSet.contains($0) }),
                  !entry.pronunciation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !entry.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  seen.insert(entry.letter).inserted else {
                throw WorldSeedError.invalidDestructibleWallLetters
            }
        }
    }

    static func loadFromBundle(
        named name: String = "letters",
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
            let catalog = LetterCatalog(
                letters: decoded.letters.map { key, spec in
                    resolveEntry(id: key, spec: spec)
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

    static func decode(from yaml: String) throws -> LetterCatalog {
        try decode(from: Data(yaml.utf8))
    }

    /// Derives tracks via `LetterSoundCatalog`; explicit keys override.
    nonisolated static func resolveEntry(id: String, spec: LetterSpec?) -> DestructibleWallLetter {
        let derivedName = LetterSoundCatalog.nameTrackID(for: id) ?? "sfx_letter_\(id.lowercased())_name"
        let derivedPronunciation = LetterSoundCatalog.pronunciationTrackID(for: id)
            ?? "sfx_letter_\(id.lowercased())_pronunciation"

        let pronunciation: String
        if let override = spec?.pronunciation?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            pronunciation = override
        } else {
            pronunciation = derivedPronunciation
        }

        let name: String
        if let override = spec?.name?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            name = override
        } else {
            name = derivedName
        }

        return DestructibleWallLetter(
            letter: id,
            pronunciation: pronunciation,
            name: name
        )
    }
}

private struct LetterCatalogDTO: Decodable {
    var fxPrefix: String?
    var letters: [String: LetterSpec?]

    enum CodingKeys: String, CodingKey {
        case fxPrefix = "fx_prefix"
        case letters
    }
}
