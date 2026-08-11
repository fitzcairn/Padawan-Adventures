import Foundation

/// Bundle location of a YAML config resource.
///
/// `Resources/Config` and `Resources/Levels` are the two explicit folders in the
/// Xcode synchronised group, so they keep their structure in the bundle and every
/// path below is rooted at one of them. This is the only place those roots appear.
nonisolated struct ConfigPath: Equatable, Sendable {
    static let configRoot = "Config"
    static let catalogRoot = "Config/Catalogs"
    static let levelRoot = "Levels"

    let basename: String
    let subdirectory: String?
    var fileExtension: String { "yaml" }

    static let app     = config("app")
    static let audio   = config("audio")
    static let player  = config("player")
    static let hud     = config("hud")
    static let screens = config("screens")

    static let enemies = ConfigPath(basename: "enemies", subdirectory: catalogRoot)
    static let items   = ConfigPath(basename: "items", subdirectory: catalogRoot)
    static let terrain = ConfigPath(basename: "terrain", subdirectory: catalogRoot)
    static let words   = ConfigPath(basename: "words", subdirectory: catalogRoot)
    static let graphemes = ConfigPath(basename: "graphemes", subdirectory: catalogRoot)
    static let strings = ConfigPath(basename: "strings", subdirectory: catalogRoot)

    static let levelDefaults = ConfigPath(basename: "_defaults", subdirectory: levelRoot)
    static let loading = ConfigPath(basename: "loading", subdirectory: "\(configRoot)/UI")
    static let cutscene = ConfigPath(basename: "cutscene", subdirectory: "\(configRoot)/UI")
    static let menu = ConfigPath(basename: "menu", subdirectory: "\(configRoot)/UI")

    /// A top-level config file, for callers that resolve by name.
    static func config(_ name: String) -> ConfigPath {
        ConfigPath(basename: name, subdirectory: configRoot)
    }

    /// A named catalog beside the standard ones, for callers that resolve by name.
    static func catalog(_ name: String) -> ConfigPath {
        ConfigPath(basename: name, subdirectory: catalogRoot)
    }

    /// Each level owns a folder holding its `level.yaml` and all of its art.
    static func level(_ name: String) -> ConfigPath {
        ConfigPath(basename: "level", subdirectory: "\(levelRoot)/\(name)")
    }

    /// Resolves an `inherits:` target: shared bases like `_defaults` sit beside the
    /// level folders, while anything else is a sibling level's own `level.yaml`.
    static func levelBase(_ name: String) -> ConfigPath {
        name.hasPrefix("_")
            ? ConfigPath(basename: name, subdirectory: levelRoot)
            : .level(name)
    }

    var description: String {
        if let subdirectory { return "\(subdirectory)/\(basename).\(fileExtension)" }
        return "\(basename).\(fileExtension)"
    }
}
