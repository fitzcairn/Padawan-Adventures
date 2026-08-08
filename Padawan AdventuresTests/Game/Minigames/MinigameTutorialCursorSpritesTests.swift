import SpriteKit
import Testing
@testable import Padawan_Adventures

@MainActor
struct MinigameTutorialCursorSpritesTests {
    @Test func loadReturnsArtForEveryPose() {
        let art = MinigameTutorialCursorSprites.load()
        #expect(art != nil)
        for pose in MinigameTutorialCursorSprites.Pose.allCases {
            #expect(art?[pose] != nil)
        }
    }

    @Test func texturesAreCachedAcrossCalls() {
        let first = MinigameTutorialCursorSprites.load()
        let second = MinigameTutorialCursorSprites.load()
        #expect(first != nil)
        #expect(second != nil)
        for pose in MinigameTutorialCursorSprites.Pose.allCases {
            #expect(first?[pose]?.texture === second?[pose]?.texture)
        }
    }

    @Test func nonMainBundleBypassesCache() {
        let main = MinigameTutorialCursorSprites.load()
        #expect(main != nil)
        let other = MinigameTutorialCursorSprites.load(
            bundle: Bundle(for: TutorialCursorBundleToken.self)
        )
        #expect(other == nil)
    }

    @Test func anchorsAreNormalized() {
        for pose in MinigameTutorialCursorSprites.Pose.allCases {
            let anchor = MinigameTutorialCursorSprites.anchor(for: pose)
            #expect(anchor.x >= 0 && anchor.x <= 1)
            #expect(anchor.y >= 0 && anchor.y <= 1)
        }
    }
}

private final class TutorialCursorBundleToken {}
