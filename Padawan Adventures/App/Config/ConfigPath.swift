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

    static func level(_ name: String) -> ConfigPath {
        ConfigPath(basename: name, subdirectory: "Levels")
    }

    var description: String {
        if let subdirectory { return "\(subdirectory)/\(basename).\(fileExtension)" }
        return "\(basename).\(fileExtension)"
    }
}
