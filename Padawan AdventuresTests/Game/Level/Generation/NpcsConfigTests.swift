import Testing
@testable import Padawan_Adventures

struct NpcsConfigTests {
    @Test func decodesSpritesWithoutFx() throws {
        let yaml = """
        sprites:
          merchant:
            root: Sprites/Merchant
            height_fraction: 1.08
        """
        let config = try NpcsConfig.decode(from: yaml)
        #expect(config.spriteConfig(id: "merchant")?.root == "Sprites/Merchant")
        #expect(config.fx(for: "merchant") == .empty)
        try config.validate()
    }

    @Test func decodesFxTablePerNpc() throws {
        let yaml = """
        fx:
          merchant:
            visible: merchant-visible
            contact: merchant-contact
        sprites:
          merchant:
            root: Sprites/Merchant
        """
        let config = try NpcsConfig.decode(from: yaml)
        #expect(config.fx(for: "merchant").trackID(for: "visible") == "merchant-visible")
        #expect(config.fx(for: "merchant").trackID(for: "contact") == "merchant-contact")
        #expect(config.fx(for: "missing") == .empty)
        try config.validate()
    }

    @Test func bundledMerchantHasVisibleAndContactFx() throws {
        let config = try NpcsConfig.loadFromBundle()
        let table = config.fx(for: "merchant")
        #expect(table.trackID(for: "visible") == "merchant-visible")
        #expect(table.trackID(for: "contact") == "merchant-contact")
    }
}
