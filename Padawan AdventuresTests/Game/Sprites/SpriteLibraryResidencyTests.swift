import CoreGraphics
import SpriteKit
import Testing
@testable import Padawan_Adventures

@MainActor
struct SpriteLibraryResidencyTests {
    @Test
    func retainDropsNonKeptIdsAndRestoresResidentBytes() {
        let library = SpriteLibrary()
        let playerTexture = Self.makeTexture(width: 16, height: 8)
        let dinoTexture = Self.makeTexture(width: 32, height: 16)

        let playerAnim = SpriteAnimation(frames: [
            SpriteFrame(texture: playerTexture, duration: 0.1),
        ])
        let dinoAnim = SpriteAnimation(frames: [
            SpriteFrame(texture: dinoTexture, duration: 0.1),
        ])

        library.seedForTesting(id: "player", animations: ["idle_down": playerAnim])
        library.seedForTesting(id: "dino", animations: ["idle_down": dinoAnim])

        let playerBytes = 16 * 8 * 4
        let dinoBytes = 32 * 16 * 4
        #expect(library.residentBytes == playerBytes + dinoBytes)

        library.retain(ids: ["player"])

        #expect(library.isLoaded(id: "dino") == false)
        #expect(library.animation(id: "dino", named: "idle_down") == nil)
        #expect(library.isLoaded(id: "player") == true)
        #expect(library.residentBytes == playerBytes)
    }

    @Test
    func uiImageConvertsOnlyFirstFrame() {
        let library = SpriteLibrary()
        let frames = (0..<3).map { _ in
            SpriteFrame(texture: Self.makeTexture(width: 8, height: 8), duration: 0.1)
        }
        library.seedForTesting(id: "icon", animations: ["idle": SpriteAnimation(frames: frames)])
        #expect(library.uiImagesCacheCount == 0)
        #expect(library.uiImage(id: "icon", named: "idle") != nil)
        #expect(library.uiImagesCacheCount == 0)
    }

    @Test
    func sharedTexturesAreCountedOnce() {
        let library = SpriteLibrary()
        let shared = Self.makeTexture(width: 10, height: 10)
        let source = SpriteAnimation(frames: [
            SpriteFrame(texture: shared, duration: 0.1),
        ])
        let flipped = source.flipped()

        library.seedForTesting(
            id: "player",
            animations: [
                "idle_right": source,
                "idle_left": flipped,
            ]
        )

        #expect(library.residentBytes == 10 * 10 * 4)
    }

    @Test
    func incompleteLoadStaysUnloadedAndCanRetry() async throws {
        let library = SpriteLibrary()
        let missing = SpriteConfig(
            root: "Sprites/Missing",
            chromaKey: "#000000",
            animations: [
                "idle_down": .sheet(sheet: "missing", atlas: "missing"),
            ]
        )
        await library.ensureLoaded(missing, id: "dino")
        #expect(library.isLoaded(id: "dino") == false)
        #expect(library.animation(id: "dino", named: "idle_down") == nil)
        #expect(library.missingAnimations(id: "dino", config: missing) == ["idle_down"])

        let real = try #require(try EnemyConfig.loadFromBundle().sprites["dino"])
        await library.ensureLoaded(real, id: "dino")
        #expect(library.isLoaded(id: "dino"))
        #expect(library.animation(id: "dino", named: "idle_down") != nil)
        #expect(library.missingAnimations(id: "dino", config: real).isEmpty)
    }

    private static func makeTexture(width: Int, height: Int) -> SKTexture {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = context.makeImage()!
        return SKTexture(cgImage: image)
    }
}
