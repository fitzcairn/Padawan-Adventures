import Foundation

/// Bundle location of a YAML config resource under `Resources/Config/`.
nonisolated struct ConfigPath: Equatable, Sendable {
    let basename: String
    let subdirectory: String?
    var fileExtension: String { "yaml" }

    static let app     = ConfigPath(basename: "app", subdirectory: nil)
    static let audio   = ConfigPath(basename: "audio", subdirectory: nil)
    static let player  = ConfigPath(basename: "player", subdirectory: nil)
    static let hud     = ConfigPath(basename: "hud", subdirectory: nil)
    static let screens = ConfigPath(basename: "screens", subdirectory: nil)

    static let enemies = ConfigPath(basename: "enemies", subdirectory: "Catalogs")
    static let items   = ConfigPath(basename: "items", subdirectory: "Catalogs")
    static let terrain = ConfigPath(basename: "terrain", subdirectory: "Catalogs")
    static let words   = ConfigPath(basename: "words", subdirectory: "Catalogs")
    static let letters = ConfigPath(basename: "letters", subdirectory: "Catalogs")

    static let levelDefaults = ConfigPath(basename: "_defaults", subdirectory: "Levels")
    static let loading = ConfigPath(basename: "loading", subdirectory: "UI")

    /// Each level owns a folder holding its `level.yaml` and all of its art.
    static func level(_ name: String) -> ConfigPath {
        ConfigPath(basename: "level", subdirectory: "Levels/\(name)")
    }

    /// Resolves an `inherits:` target: shared bases like `_defaults` sit beside the
    /// level folders, while anything else is a sibling level's own `level.yaml`.
    static func levelBase(_ name: String) -> ConfigPath {
        name.hasPrefix("_")
            ? ConfigPath(basename: name, subdirectory: "Levels")
            : .level(name)
    }

    var description: String {
        if let subdirectory { return "\(subdirectory)/\(basename).\(fileExtension)" }
        return "\(basename).\(fileExtension)"
    }
}
