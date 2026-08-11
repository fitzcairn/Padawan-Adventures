import Foundation
import os

/// A playable level discovered from `Resources/Levels/<id>/`.
nonisolated struct LevelDescriptor: Equatable, Sendable {
    let resourceName: String
    /// `strings.yaml` id for the level display name / VO (`level.name` in YAML).
    let nameStringID: String
    /// Resolved copy from `Strings.text(nameStringID)`.
    let displayName: String
    let order: Int
    /// Hex fill for the level-select planet sprite.
    let color: String
    /// Level-select planet art from the level YAML `sprite:` block.
    let sprite: SpriteConfig?
    /// Item id for this level's treasure part, shown in the inventory once earned.
    let treasure: String?
    /// SF Symbol awarded on completion; the inventory glyph fallback.
    let artifact: String
}

nonisolated enum LevelCatalog {
    static let subdirectory = ConfigPath.levelRoot
    private static let logger = Logger(subsystem: "PadawanAdventures", category: "LevelCatalog")

    static func loadFromBundle(
        withExtension ext: String = "yaml",
        wordCatalog: WordCatalog? = nil,
        graphemeCatalog: GraphemeCatalog? = nil,
        vocabularyCatalog: LevelVocabularyCatalog? = nil
    ) -> [LevelDescriptor] {
        let sharedVocabulary: LevelVocabularyCatalog?
        if let vocabularyCatalog {
            sharedVocabulary = vocabularyCatalog
        } else {
            sharedVocabulary = try? LevelVocabularyCatalog.loadFromBundle()
        }
        return levelIDs().compactMap { resourceName -> LevelDescriptor? in
            do {
                let level = try LevelConfig.loadFromBundle(
                    named: resourceName,
                    withExtension: ext,
                    subdirectory: subdirectory,
                    wordCatalog: wordCatalog,
                    graphemeCatalog: graphemeCatalog,
                    vocabularyCatalog: sharedVocabulary
                )
                return LevelDescriptor(
                    resourceName: resourceName,
                    nameStringID: level.name,
                    displayName: Strings.text(level.name),
                    order: level.order,
                    color: level.color,
                    sprite: level.sprite,
                    treasure: level.treasure,
                    artifact: level.artifact
                )
            } catch {
                logger.error(
                    "Failed to load level '\(resourceName, privacy: .public)': \(String(describing: error), privacy: .public)"
                )
                return nil
            }
        }
        .sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.resourceName < $1.resourceName
        }
    }

    /// Every directory under `Levels/` is a playable level, so adding one needs no code
    /// change. Names beginning with `_` are shared config (`_defaults.yaml`), not levels.
    static func levelIDs() -> [String] {
        guard let root = Bundle.main.resourceURL?
            .appendingPathComponent(subdirectory, isDirectory: true) else { return [] }
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? []
        return entries.compactMap { url in
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory
            guard isDirectory == true else { return nil }
            let name = url.lastPathComponent
            return name.hasPrefix("_") ? nil : name
        }
    }
}
