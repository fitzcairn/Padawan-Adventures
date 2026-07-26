import Testing
@testable import Padawan_Adventures

struct UISpritesConfigTests {
    @Test func decodesPlanetSpriteBlocks() throws {
        let yaml = """
        music: menu_theme
        tython:
          sprite:
            root: Sprites/UI/Levels
            chroma_key: "#000000"
            chroma_key_tolerance: 2
            animations:
              idle:
                sheet: 1-tython
                atlas: 1-tython-atlas
        tatooine:
          sprite:
            root: Sprites/UI/Levels
            chroma_key: "#000000"
            animations:
              idle:
                sheet: 2-tatooine
                atlas: 2-tatooine-atlas
        """
        let config = try UISpritesConfig.decode(from: yaml)
        let tython = try #require(config.sprites["tython"]?.sprite)
        #expect(tython.root == "Sprites/UI/Levels")
        #expect(tython.chromaKey == "#000000")
        #expect(tython.chromaKeyTolerance == 2)
        #expect(config.spriteConfig(for: "tython") != nil)
        #expect(config.spriteConfig(for: "tatooine") != nil)
        #expect(config.spriteConfig(for: "missing") == nil)
        #expect(config.sprites["music"] == nil)
        try config.validate()
    }

    @Test func validateRejectsEmptySpriteRoot() {
        let config = UISpritesConfig(sprites: [
            "tython": UISpriteDefinition(
                sprite: SpriteConfig(root: "   ", chromaKey: "#000000")
            ),
        ])
        #expect(throws: UISpritesConfigError.invalid("tython.sprite.root must be non-empty")) {
            try config.validate()
        }
    }

    @Test func emptyFallbackHasNoSprites() {
        #expect(UISpritesConfig.fallback.sprites.isEmpty)
    }

    @Test func loadsBundledUISpritesYAML() throws {
        let config = try UISpritesConfig.loadFromBundle()
        try config.validate()
        #expect(config.spriteConfig(for: "tython") != nil)
        #expect(config.spriteConfig(for: "geonosis") != nil)
        #expect(config.sprites.count == 8)
    }
}
