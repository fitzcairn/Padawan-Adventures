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

    @Test func decodesTreasurePartSpriteWithoutChroma() throws {
        let yaml = """
        emitter:
          sprite:
            root: Levels/1-tython
            scale: 0.4
            animations:
              idle:
                sheet: 1-emitter-spritesheet
                atlas: 1-emitter-atlas
        """
        let config = try ItemsConfig.decode(from: yaml)
        let sprite = try #require(config.spriteConfig(id: "emitter"))
        #expect(sprite.root == "Levels/1-tython")
        #expect(sprite.chromaKey == nil)
        #expect(sprite.scale == 0.4)
        #expect(config.spriteConfig(for: .treasure) == nil)
        #expect(config.highlight(id: "emitter") == nil)
    }

    @Test func decodesHighlightBlock() throws {
        let yaml = """
        emitter:
          sprite:
            root: Levels/1-tython
            scale: 1.0
            animations:
              idle:
                sheet: 1-emitter-spritesheet
                atlas: 1-emitter-atlas
          highlight:
            color: "#FFD54F"
            birth_rate: 22
            lifetime: 1.1
            radius: 0.45
            particle_size: 0.12
            alpha: 0.85
            y_offset: 0.45
        """
        let config = try ItemsConfig.decode(from: yaml)
        let highlight = try #require(config.highlight(id: "emitter"))
        #expect(highlight.color == "#FFD54F")
        #expect(highlight.birthRate == 22)
        #expect(highlight.lifetime == 1.1)
        #expect(highlight.radius == 0.45)
        #expect(highlight.particleSize == 0.12)
        #expect(highlight.alpha == 0.85)
        #expect(highlight.yOffset == 0.45)
        try config.validate()
    }

    @Test func highlightUsesDefaultsForOmittedKeys() throws {
        let yaml = """
        emitter:
          sprite:
            root: Levels/1-tython
          highlight:
            color: "#FFFFFF"
        """
        let config = try ItemsConfig.decode(from: yaml)
        let highlight = try #require(config.highlight(id: "emitter"))
        #expect(highlight.color == "#FFFFFF")
        #expect(highlight.birthRate == 22)
        #expect(highlight.lifetime == 1.1)
        #expect(highlight.radius == 0.45)
        #expect(highlight.particleSize == 0.12)
        #expect(highlight.alpha == 0.85)
        #expect(highlight.yOffset == 0.45)
    }

    @Test func validateRejectsBadHighlightColor() {
        let config = ItemsConfig(items: [
            "emitter": ItemDefinition(
                sprite: SpriteConfig(root: "x"),
                highlight: HighlightConfig(color: "nope")
            ),
        ])
        #expect(throws: ItemsConfigError.invalid(
            "emitter.highlight.color must be a hex color like #RRGGBB"
        )) {
            try config.validate()
        }
    }
}
