import Testing
@testable import Padawan_Adventures

struct HudConfigTests {
    @Test func decodesSampleYAML() throws {
        let yaml = """
        icon_size: 40
        icon_spacing: 10
        score_text_gap: 10
        """

        let config = try HudConfig.decode(from: yaml)
        #expect(config.iconSize == 40)
        #expect(config.iconSpacing == 10)
        #expect(config.scoreTextGap == 10)
        try config.validate()
    }

    @Test func decodesCustomSizing() throws {
        let yaml = """
        icon_size: 48
        icon_spacing: 12
        score_text_gap: 8
        """

        let config = try HudConfig.decode(from: yaml)
        #expect(config.iconSize == 48)
        #expect(config.iconSpacing == 12)
        #expect(config.scoreTextGap == 8)
        try config.validate()
    }

    @Test func fallbackMatchesExpectedDefaults() {
        let config = HudConfig.fallback
        #expect(config.iconSize == 40)
        #expect(config.iconSpacing == 10)
        #expect(config.scoreTextGap == 10)
    }

    @Test func validateRejectsNonPositiveIconSize() {
        var config = HudConfig.fallback
        config.iconSize = 0
        #expect(throws: HudConfigError.invalid("icon_size must be > 0")) {
            try config.validate()
        }
    }

    @Test func validateRejectsNonPositiveSpacing() {
        var config = HudConfig.fallback
        config.iconSpacing = -1
        #expect(throws: HudConfigError.invalid("icon_spacing must be > 0")) {
            try config.validate()
        }
    }

    @Test func decodeFailsOnInvalidYAML() {
        #expect(throws: HudConfigError.decodeFailed) {
            try HudConfig.decode(from: "icon_size: [not, valid]")
        }
    }
}
