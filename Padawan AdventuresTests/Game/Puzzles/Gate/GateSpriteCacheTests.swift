import SpriteKit
import Testing
@testable import Padawan_Adventures

@MainActor
struct GateSpriteCacheTests {
    @Test func switchTexturesAreCachedAcrossCalls() {
        let first = GateLetterMatchSwitchSprites.load()
        let second = GateLetterMatchSwitchSprites.load()
        #expect(first != nil)
        #expect(second != nil)
        #expect(first?.off === second?.off)
        #expect(first?.on === second?.on)
    }

    @Test func capacitorTextureIsCachedAcrossCalls() {
        let first = GateSpellingCapacitorSprites.load()
        let second = GateSpellingCapacitorSprites.load()
        #expect(first != nil)
        #expect(second != nil)
        #expect(first === second)
    }

    @Test func nonMainBundleBypassesSwitchCache() {
        let main = GateLetterMatchSwitchSprites.load()
        #expect(main != nil)
        let other = GateLetterMatchSwitchSprites.load(bundle: Bundle(for: BundleToken.self))
        // Test bundle has no switch art; must not return the cached .main textures.
        #expect(other == nil)
    }
}

private final class BundleToken {}
