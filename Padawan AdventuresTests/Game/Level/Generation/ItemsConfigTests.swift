import Testing
@testable import Padawan_Adventures

struct ItemsConfigTests {
    @Test func decodesEnergySpriteBlock() throws {
        let yaml = """
        energy:
          sprite:
            root: Sprites/Items/Energy
            chroma_key: "#000000"
            scale: 0.6
            animations:
              idle:
                sheet: energy-spritesheet
                atlas: energy-atlas
        """
        let config = try ItemsConfig.decode(from: yaml)
        let energy = config.items["energy"]
        #expect(energy != nil)
        let sprite = try #require(energy?.sprite)
        #expect(sprite.root == "Sprites/Items/Energy")
        #expect(sprite.chromaKey == "#000000")
        #expect(sprite.scale == 0.6)
        #expect(config.spriteConfig(for: .energy) != nil)
        #expect(config.spriteConfig(for: .health) == nil)
        try config.validate()
    }

    @Test func validateRejectsEmptySpriteRoot() {
        let config = ItemsConfig(items: [
            "energy": ItemDefinition(
                sprite: SpriteConfig(root: "   ", chromaKey: "#000000")
            ),
        ])
        #expect(throws: ItemsConfigError.invalid("energy.sprite.root must be non-empty")) {
            try config.validate()
        }
    }

    @Test func emptyFallbackHasNoItems() {
        #expect(ItemsConfig.fallback.items.isEmpty)
    }
}
