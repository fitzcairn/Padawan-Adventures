import Testing
@testable import Padawan_Adventures

struct ItemsConfigTests {
    @Test func decodesEnergyAndHealthSpriteBlocks() throws {
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
        health:
          sprite:
            root: Sprites/Items/Health
            chroma_key: "#000000"
            scale: 0.6
            animations:
              idle:
                sheet: health-spritesheet
                atlas: health-atlas
        """
        let config = try ItemsConfig.decode(from: yaml)
        let energy = try #require(config.items["energy"]?.sprite)
        #expect(energy.root == "Sprites/Items/Energy")
        #expect(energy.chromaKey == "#000000")
        #expect(energy.scale == 0.6)
        let health = try #require(config.items["health"]?.sprite)
        #expect(health.root == "Sprites/Items/Health")
        #expect(health.chromaKey == "#000000")
        #expect(health.scale == 0.6)
        #expect(config.spriteConfig(for: .energy) != nil)
        #expect(config.spriteConfig(for: .health) != nil)
        #expect(config.spriteConfig(for: .treasure) == nil)
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
