import CoreGraphics
import Foundation
import SpriteKit
import Testing
@testable import Padawan_Adventures

struct SpriteSystemTests {
    @Test func atlasDecodesOrderedFramesAndDurations() throws {
        let json = """
        {
          "frames": {
            "2": { "x": 512, "y": 0, "w": 256, "h": 256, "duration": 1 },
            "0": { "x": 0, "y": 0, "w": 256, "h": 256, "duration": 1 },
            "1": { "x": 256, "y": 0, "w": 256, "h": 256, "duration": 1 }
          },
          "meta": {
            "size": { "w": 768, "h": 256 },
            "frame_size": { "w": 256, "h": 256 },
            "duration_s": 1.5
          }
        }
        """
        let atlas = try SpriteAtlas.decode(from: Data(json.utf8))
        #expect(atlas.orderedFrames.map(\.key) == ["0", "1", "2"])
        let durations = atlas.frameDurationsSeconds()
        #expect(durations.count == 3)
        // Equal weights share meta.duration_s (1.5s / 3 frames).
        #expect(abs(durations[0] - 0.5) < 0.000_1)
        #expect(abs(durations[1] - 0.5) < 0.000_1)
        #expect(abs(durations[2] - 0.5) < 0.000_1)
        #expect(abs(durations.reduce(0, +) - 1.5) < 0.000_1)
    }

    @Test func atlasDurationsScaleByFrameWeights() throws {
        let json = """
        {
          "frames": {
            "0": { "x": 0, "y": 0, "w": 16, "h": 16, "duration": 1 },
            "1": { "x": 16, "y": 0, "w": 16, "h": 16, "duration": 3 }
          },
          "meta": { "duration_s": 2.0 }
        }
        """
        let atlas = try SpriteAtlas.decode(from: Data(json.utf8))
        let durations = atlas.frameDurationsSeconds()
        #expect(abs(durations[0] - 0.5) < 0.000_1)
        #expect(abs(durations[1] - 1.5) < 0.000_1)
    }

    @Test func opaqueContentBoundsIgnoresTransparentPadding() throws {
        // 3x3: opaque center pixel only.
        let width = 3
        let height = 3
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let center = (1 * width + 1) * 4
        pixels[center] = 255
        pixels[center + 1] = 0
        pixels[center + 2] = 0
        pixels[center + 3] = 255

        let space = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            Issue.record("Failed to build fixture CGImage")
            return
        }

        let bounds = try #require(SpriteSheetLoader.opaqueContentBounds(of: image))
        #expect(bounds == CGRect(x: 1, y: 1, width: 1, height: 1))

        let trimmed = SpriteSheetLoader.trimToSharedOpaqueBounds([image])
        #expect(trimmed.count == 1)
        #expect(trimmed[0].width == 1)
        #expect(trimmed[0].height == 1)
    }

    @Test func chromaKeyClearsExactBackgroundOnly() throws {
        let width = 3
        let height = 1
        var pixels: [UInt8] = [
            0, 0, 0, 255, // exact key
            8, 8, 8, 255, // near-black — must remain opaque
            255, 0, 0, 255, // red
        ]
        let space = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            Issue.record("Failed to build fixture CGImage")
            return
        }

        let keyed = SpriteSheetLoader.applyChromaKey(to: image, key: (0, 0, 0))

        guard let data = keyed.dataProvider?.data as Data? else {
            Issue.record("Missing pixel data")
            return
        }
        // Exact black keyed out; near-black and red preserved.
        #expect(data[3] == 0)
        #expect(data[4] == 8)
        #expect(data[7] == 255)
        #expect(data[8] == 255)
        #expect(data[11] == 255)
    }

    @Test func parseHexRGB() {
        let rgb = SpriteSheetLoader.parseHexRGB("#000000")
        #expect(rgb?.r == 0)
        #expect(rgb?.g == 0)
        #expect(rgb?.b == 0)
        #expect(SpriteSheetLoader.parseHexRGB("ff00aa")?.r == 255)
        #expect(SpriteSheetLoader.parseHexRGB("bad") == nil)
    }

    @Test @MainActor func flipOfSharesFramesAndSetsFlipFlag() {
        let texture = SKTexture()
        let source = SpriteAnimation(
            frames: [SpriteFrame(texture: texture, duration: 0.1)],
            flipsHorizontally: false
        )
        var loaded = ["idle_northeast": source]
        SpriteLibrary.resolveFlipAnimations(
            into: &loaded,
            flipSources: [("idle_northwest", "idle_northeast")]
        )
        let flipped = loaded["idle_northwest"]
        #expect(flipped?.flipsHorizontally == true)
        #expect(flipped?.frames.count == 1)
        #expect(loaded["idle_northeast"]?.flipsHorizontally == false)
    }

    @Test func spriteDisplayHeightMatchesWallHeightTimesMultiplier() {
        let sprite = SpriteConfig(root: "Sprites/Player", sizeMultiplier: 1.2)
        let iso = IsometricConfig(tileWidth: 80, tileHeight: 40, wallHeight: 80)
        let height = PlaceholderFactory.spriteDisplayHeight(isoConfig: iso, spriteConfig: sprite)
        #expect(abs(height - 96) < 0.001) // 80 * 1.2
        let size = PlaceholderFactory.spriteDisplaySize(isoConfig: iso, spriteConfig: sprite)
        #expect(abs(size.height - 96) < 0.001)
        #expect(abs(size.width - 96) < 0.001) // provisional square; width refined from texture aspect
    }

    @Test func compassDirectionMapsGridStepToScreenFacing() {
        // Iso projection: screen up = decreasing x+y, screen right = increasing x-y.
        #expect(CompassDirection(dx: -1, dy: -1) == .up)          // upper middle
        #expect(CompassDirection(dx: 0, dy: -1) == .northeast)    // upper right
        #expect(CompassDirection(dx: 1, dy: -1) == .right)        // right
        #expect(CompassDirection(dx: 1, dy: 0) == .southeast)     // lower right
        #expect(CompassDirection(dx: 1, dy: 1) == .down)          // lower middle
        #expect(CompassDirection(dx: 0, dy: 1) == .southwest)     // lower left
        #expect(CompassDirection(dx: -1, dy: 1) == .left)         // left
        #expect(CompassDirection(dx: -1, dy: 0) == .northwest)    // upper left
        #expect(CompassDirection(dx: 2, dy: 0) == nil)

        for direction in CompassDirection.allCases {
            #expect(CompassDirection(dx: direction.dx, dy: direction.dy) == direction)
        }
        #expect(CompassDirection.down.animationName(locomotion: .idle) == "idle_down")
        #expect(CompassDirection.southeast.animationName(locomotion: .walk) == "walk_southeast")
    }

    @Test @MainActor func spriteLibraryEnsureLoadedIsIdempotent() {
        let library = SpriteLibrary()
        let config = SpriteConfig(
            root: "Sprites/Missing",
            chromaKey: "#000000",
            animations: [
                "idle_down": .sheet(sheet: "missing", atlas: "missing"),
            ]
        )
        library.ensureLoaded(config, id: "player")
        #expect(library.isLoaded(id: "player"))
        let countAfterFirst = library.animationCount(for: "player")
        library.ensureLoaded(config, id: "player")
        #expect(library.animationCount(for: "player") == countAfterFirst)
    }

    @Test @MainActor func spriteLibrarySeedPreservesAnimations() {
        let library = SpriteLibrary()
        let anim = SpriteAnimation(
            frames: [SpriteFrame(texture: SKTexture(), duration: 0.2)],
            flipsHorizontally: false
        )
        library.seedForTesting(id: "player", animations: ["idle_down": anim])
        #expect(library.isLoaded(id: "player"))
        #expect(library.animation(named: "idle_down") != nil)

        let config = SpriteConfig(root: "Sprites/Player", animations: [:])
        library.ensureLoaded(config, id: "player")
        #expect(library.animation(named: "idle_down") != nil)
    }

    @Test @MainActor func loadsPlayerIdleDownFromBundle() throws {
        let config = try PlayerConfig.loadFromBundle()
        let sprite = try #require(config.sprite)
        let library = SpriteLibrary()
        library.ensureLoaded(sprite, id: "player")
        let idle = try #require(library.animation(named: "idle_down"))
        #expect(!idle.frames.isEmpty)
        #expect(idle.flipsHorizontally == false)
        let northwest = try #require(library.animation(named: "idle_northwest"))
        #expect(northwest.flipsHorizontally == true)
        #expect(northwest.frames.count == idle.frames.count || library.animation(named: "idle_northeast") != nil)
        #expect(library.animationCount(for: "player") >= 10)
    }

    @Test func playerConfigDecodesSpriteSection() throws {
        let yaml = """
        letter: P
        starting_health: 3
        starting_energy: 2
        sprite:
          root: Sprites/Player
          chroma_key: "#000000"
          size_multiplier: 1.2
          anchor_correction: 2
          animations:
            idle_down:
              sheet: idle_down
              atlas: idle_down
            idle_northwest:
              flip_of: idle_northeast
            idle_up: idle_up
        """
        let config = try PlayerConfig.decode(from: yaml)
        let sprite = try #require(config.sprite)
        #expect(sprite.root == "Sprites/Player")
        #expect(sprite.chromaKey == "#000000")
        #expect(sprite.sizeMultiplier == 1.2)
        #expect(sprite.anchorCorrection == 2)
        #expect(sprite.animations["idle_down"] == .sheet(sheet: "idle_down", atlas: "idle_down"))
        #expect(sprite.animations["idle_northwest"] == .flipOf("idle_northeast"))
        #expect(sprite.animations["idle_up"] == .sheet(sheet: "idle_up", atlas: "idle_up"))
    }
}
