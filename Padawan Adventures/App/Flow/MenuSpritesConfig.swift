import Foundation

/// Main-menu sprite definitions from `Resources/Config/UI/menu.yaml`.
struct MenuSpritesConfig: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        var sprite: SpriteConfig
    }

    static let iconsID = "menu_icons"

    /// Frame order matches the 2×2 sheet (row-major): Continue, New Game, Settings, Exit.
    enum Icon: Int, CaseIterable {
        case continueGame = 0
        case newGame = 1
        case settings = 2
        case exit = 3
    }

    var menu_icons: Entry

    var entries: [(id: String, config: SpriteConfig)] {
        [(id: Self.iconsID, config: menu_icons.sprite)]
    }

    static func loadFromBundle(bundle: Bundle = .main) throws -> MenuSpritesConfig {
        try ConfigStore.load(MenuSpritesConfig.self, from: .menu, bundle: bundle)
    }
}
