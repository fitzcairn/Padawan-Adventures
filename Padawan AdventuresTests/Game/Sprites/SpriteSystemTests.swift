import CoreGraphics
import Foundation
import SpriteKit
import Testing
import Yams
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

    @Test func flipAroundXAxisSwapsTopAndBottom() throws {
        let width = 1
        let height = 2
        var pixels: [UInt8] = [
            255, 0, 0, 255, // top: red
            0, 0, 255, 255, // bottom: blue
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

        let flipped = SpriteSheetLoader.flipAroundXAxis(image)
        let top = try #require(rgbaBytes(of: flipped, crop: CGRect(x: 0, y: 0, width: 1, height: 1)))
        let bottom = try #require(rgbaBytes(of: flipped, crop: CGRect(x: 0, y: 1, width: 1, height: 1)))
        #expect(top[2] == 255) // blue now on top
        #expect(bottom[0] == 255) // red now on bottom
    }

    @Test func flipAroundYAxisSwapsLeftAndRight() throws {
        let width = 2
        let height = 1
        var pixels: [UInt8] = [
            255, 0, 0, 255, // left: red
            0, 0, 255, 255, // right: blue
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

        let flipped = SpriteSheetLoader.flipAroundYAxis(image)
        let left = try #require(rgbaBytes(of: flipped, crop: CGRect(x: 0, y: 0, width: 1, height: 1)))
        let right = try #require(rgbaBytes(of: flipped, crop: CGRect(x: 1, y: 0, width: 1, height: 1)))
        #expect(left[2] == 255) // blue now on left
        #expect(right[0] == 255) // red now on right
    }

    @Test func opaqueContentBoundsUsesTopLeftOrigin() throws {
        // 3x2: only the top-right pixel is opaque — catches Y flips in bounds math.
        let width = 3
        let height = 2
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let topRight = (0 * width + 2) * 4
        pixels[topRight] = 0
        pixels[topRight + 1] = 255
        pixels[topRight + 2] = 0
        pixels[topRight + 3] = 255

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
        #expect(bounds == CGRect(x: 2, y: 0, width: 1, height: 1))
    }

    @Test func chromaKeyPreservesSpritesheetTopLeftOrigin() throws {
        // Regression: a Y-flip inside chroma-key makes atlas (0,0) read the bottom row.
        let sheetURL = try #require(
            Bundle.main.url(forResource: "idle_northeast-spritesheet", withExtension: "png")
        )
        let original = try #require(UIImage(contentsOfFile: sheetURL.path)?.cgImage)
        let keyed = SpriteSheetLoader.applyChromaKey(to: original, key: (0, 0, 0))

        #expect(keyed.width == original.width)
        #expect(keyed.height == original.height)

        // Find a distinctive non-key pixel in the top-left atlas cell and require it
        // still lives in that cell after chroma (not mirrored to the bottom row).
        let cell = 256
        var probe: (x: Int, y: Int, rgba: [UInt8])?
        outer: for y in 0..<cell {
            for x in 0..<cell {
                let rgba = try #require(rgbaBytes(of: original, crop: CGRect(x: x, y: y, width: 1, height: 1)))
                if rgba[3] > 0, !(rgba[0] == 0 && rgba[1] == 0 && rgba[2] == 0) {
                    probe = (x, y, rgba)
                    break outer
                }
            }
        }
        let found = try #require(probe)

        let after = try #require(
            rgbaBytes(of: keyed, crop: CGRect(x: found.x, y: found.y, width: 1, height: 1))
        )
        #expect(after[0] == found.rgba[0])
        #expect(after[1] == found.rgba[1])
        #expect(after[2] == found.rgba[2])

        // If chroma vertically flipped the sheet, the same color would appear at mirrored Y.
        let mirroredY = original.height - 1 - found.y
        let mirrored = try #require(
            rgbaBytes(of: keyed, crop: CGRect(x: found.x, y: mirroredY, width: 1, height: 1))
        )
        let mirroredMatches =
            mirrored[0] == found.rgba[0]
            && mirrored[1] == found.rgba[1]
            && mirrored[2] == found.rgba[2]
            && mirrored[3] > 0
        let sameAsProbeLocation =
            after[0] == found.rgba[0]
            && after[1] == found.rgba[1]
            && after[2] == found.rgba[2]
        #expect(sameAsProbeLocation)
        // Mirrored cell must not be the only place that color landed.
        if mirroredMatches {
            #expect(mirroredY == found.y)
        }
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

    @Test func spriteDisplayHeightMatchesWallHeightTimesScale() {
        let sprite = SpriteConfig(root: "Sprites/Player", scale: 1.2)
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

    @Test @MainActor func loadsLevelPlanetUISpriteFromBundle() async throws {
        let level = try LevelConfig.loadFromBundle(
            named: "1-tython",
            subdirectory: LevelCatalog.subdirectory
        )
        let sprite = try #require(level.sprite)
        #expect(sprite.root == "Sprites/UI/Levels")
        #expect(sprite.chromaKey == "#000000")
        #expect(sprite.chromaKeyTolerance == 2)
        guard case .sheet(let sheet, let atlas) = sprite.animations["idle"] else {
            Issue.record("Expected tython idle sheet animation")
            return
        }
        #expect(sheet == "1-tython")
        #expect(atlas == "1-tython-atlas")
        let library = SpriteLibrary()
        await library.ensureLoaded(sprite, id: "1-tython")
        let idle = try #require(library.animation(id: "1-tython", named: "idle"))
        #expect(idle.frames.count == 1)
        let size = idle.frames[0].texture.size()
        #expect(size.width > 0)
        #expect(size.height > 0)
        let uiImage = try #require(library.uiImage(id: "1-tython", named: "idle"))
        #expect(uiImage.size.width > 0)
        #expect(uiImage.size.height > 0)
    }

    @Test @MainActor func spriteLibraryEnsureLoadedIsIdempotent() async {
        let library = SpriteLibrary()
        let config = SpriteConfig(
            root: "Sprites/Missing",
            chromaKey: "#000000",
            animations: [
                "idle_down": .sheet(sheet: "missing", atlas: "missing"),
            ]
        )
        await library.ensureLoaded(config, id: "player")
        #expect(library.isLoaded(id: "player"))
        let countAfterFirst = library.animationCount(for: "player")
        await library.ensureLoaded(config, id: "player")
        #expect(library.animationCount(for: "player") == countAfterFirst)
    }

    @Test @MainActor func spriteLibrarySeedPreservesAnimations() async {
        let library = SpriteLibrary()
        let anim = SpriteAnimation(
            frames: [SpriteFrame(texture: SKTexture(), duration: 0.2)],
            flipsHorizontally: false
        )
        library.seedForTesting(id: "player", animations: ["idle_down": anim])
        #expect(library.isLoaded(id: "player"))
        #expect(library.animation(named: "idle_down") != nil)

        let config = SpriteConfig(root: "Sprites/Player", animations: [:])
        await library.ensureLoaded(config, id: "player")
        #expect(library.animation(named: "idle_down") != nil)
    }

    @Test @MainActor func loadsPlayerIdleDownFromBundle() async throws {
        let config = try PlayerConfig.loadFromBundle()
        let sprite = try #require(config.sprite)
        let library = SpriteLibrary()
        await library.ensureLoaded(sprite, id: "player")
        let idle = try #require(library.animation(named: "idle_down"))
        #expect(idle.frames.count == 25)
        #expect(idle.flipsHorizontally == false)
        // Shared opaque trim: frames are smaller than the 256×256 atlas cell and equal-sized.
        let firstSize = idle.frames[0].texture.size()
        #expect(firstSize.width > 0 && firstSize.width <= 256)
        #expect(firstSize.height > 0 && firstSize.height <= 256)
        #expect(firstSize.width < 256 || firstSize.height < 256)
        for frame in idle.frames {
            #expect(abs(frame.texture.size().width - firstSize.width) < 0.5)
            #expect(abs(frame.texture.size().height - firstSize.height) < 0.5)
        }
        let expectedDuration = 2.042 / 25
        for frame in idle.frames {
            #expect(abs(frame.duration - expectedDuration) < 0.000_1)
        }
        let northwest = try #require(library.animation(named: "idle_northwest"))
        #expect(northwest.flipsHorizontally == true)
        #expect(northwest.frames.count == idle.frames.count)
        #expect(library.animationCount(for: "player") >= 10)
    }

    @Test @MainActor func idleNortheastLoopMatchesAtlasDuration() async throws {
        let config = try PlayerConfig.loadFromBundle()
        let sprite = try #require(config.sprite)
        let library = SpriteLibrary()
        await library.ensureLoaded(sprite, id: "player")

        let idle = try #require(library.animation(named: "idle_northeast"))
        #expect(idle.frames.count == 25)

        let expectedLoop: TimeInterval = 2.042
        let expectedFrame = expectedLoop / 25
        let loopSum = idle.frames.reduce(0.0) { $0 + $1.duration }
        #expect(abs(loopSum - expectedLoop) < 0.000_1)
        for frame in idle.frames {
            #expect(abs(frame.duration - expectedFrame) < 0.000_1)
        }

        // Playback uses SKAction.animate when durations are uniform.
        let durations = idle.frames.map(\.duration)
        #expect(durations.allSatisfy { abs($0 - expectedFrame) < 0.000_001 })
    }

    @Test @MainActor func idleNortheastPlaysSpritesheetTopLeftToBottomRight() throws {
        let atlasURL = try #require(
            Bundle.main.url(forResource: "idle_northeast-atlas", withExtension: "json")
        )
        let atlas = try SpriteAtlas.decode(from: Data(contentsOf: atlasURL))
        let ordered = atlas.orderedFrames
        #expect(ordered.map(\.key) == (0..<25).map(String.init))

        let frameW = 256
        let frameH = 256
        let columns = 5
        for (index, entry) in ordered.enumerated() {
            let expectedX = (index % columns) * frameW
            let expectedY = (index / columns) * frameH
            #expect(entry.frame.x == expectedX)
            #expect(entry.frame.y == expectedY)
            #expect(entry.frame.w == frameW)
            #expect(entry.frame.h == frameH)
        }

        let sheetURL = try #require(
            Bundle.main.url(forResource: "idle_northeast-spritesheet", withExtension: "png")
        )
        let sheetImage = try #require(UIImage(contentsOfFile: sheetURL.path)?.cgImage)
        let keyed = SpriteSheetLoader.applyChromaKey(
            to: sheetImage,
            key: (r: 0, g: 0, b: 0)
        )

        var atlasCrops: [CGImage] = []
        for entry in ordered {
            let crop = CGRect(
                x: entry.frame.x,
                y: entry.frame.y,
                width: entry.frame.w,
                height: entry.frame.h
            )
            atlasCrops.append(try #require(keyed.cropping(to: crop)))
        }
        let expectedTrimmed = SpriteSheetLoader.trimToSharedOpaqueBounds(atlasCrops)
            .map(SpriteSheetLoader.flipAroundXAxis)

        // Production load path (same as SpriteLibrary / AnimatedSpriteNode).
        let idle = try SpriteSheetLoader.loadAnimation(
            sheet: "idle_northeast-spritesheet",
            atlas: "idle_northeast-atlas",
            root: "Sprites/Player",
            chromaKey: "#000000"
        )
        #expect(idle.frames.count == expectedTrimmed.count)

        // Each playable frame must be the trimmed+X-flipped atlas crop at that index.
        // SKTexture.cgImage() may V-invert relative to the source crop — accept either.
        for (index, expectedCrop) in expectedTrimmed.enumerated() {
            let expected = try #require(rgbaBytes(of: expectedCrop))
            let expectedFlipped = try #require(rgbaBytes(of: expectedCrop, flipVertically: true))

            let textureImage = idle.frames[index].texture.cgImage()
            let actual = try #require(rgbaBytes(of: textureImage))
            #expect(actual == expected || actual == expectedFlipped)

            if index + 1 < expectedTrimmed.count {
                let nextPixels = try #require(rgbaBytes(of: expectedTrimmed[index + 1]))
                #expect(actual != nextPixels)
            }
        }
    }

    @Test func spriteConfigTrimDefaultsToTrue() throws {
        let config = try YAMLDecoder().decode(
            SpriteConfig.self,
            from: Data("""
            root: Sprites/Player
            """.utf8)
        )
        #expect(config.trim == true)
        #expect(SpriteConfig(root: "Sprites/Player").trim == true)
    }

    @Test func loadAnimationTrimFalseKeepsAtlasRectSize() throws {
        let atlasURL = try #require(
            Bundle.main.url(
                forResource: "idle_northeast-atlas",
                withExtension: "json",
                subdirectory: "Sprites/Player"
            ) ?? Bundle.main.url(forResource: "idle_northeast-atlas", withExtension: "json")
        )
        let atlas = try SpriteAtlas.decode(from: Data(contentsOf: atlasURL))
        let frame = try #require(atlas.orderedFrames.first?.frame)

        let trimmed = try SpriteSheetLoader.loadAnimation(
            sheet: "idle_northeast-spritesheet",
            atlas: "idle_northeast-atlas",
            root: "Sprites/Player",
            chromaKey: "#000000",
            trim: true
        )
        let untrimmed = try SpriteSheetLoader.loadAnimation(
            sheet: "idle_northeast-spritesheet",
            atlas: "idle_northeast-atlas",
            root: "Sprites/Player",
            chromaKey: "#000000",
            trim: false
        )

        let untrimmedSize = untrimmed.frames[0].texture.size()
        #expect(Int(untrimmedSize.width.rounded()) == frame.w)
        #expect(Int(untrimmedSize.height.rounded()) == frame.h)

        let trimmedSize = trimmed.frames[0].texture.size()
        #expect(trimmedSize.width <= untrimmedSize.width)
        #expect(trimmedSize.height <= untrimmedSize.height)
        #expect(trimmedSize != untrimmedSize)
    }

    @Test func playerConfigDecodesSpriteSection() throws {
        let yaml = """
        letter: P
        starting_health: 3
        starting_energy: 2
        sprite:
          root: Sprites/Player
          chroma_key: "#000000"
          scale: 1.2
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
        #expect(sprite.scale == 1.2)
        #expect(sprite.anchorCorrection == 2)
        #expect(sprite.animations["idle_down"] == .sheet(sheet: "idle_down", atlas: "idle_down"))
        #expect(sprite.animations["idle_northwest"] == .flipOf("idle_northeast"))
        #expect(sprite.animations["idle_up"] == .sheet(sheet: "idle_up", atlas: "idle_up"))
    }

    @Test func spriteConfigExpandsChromaPresets() throws {
        let black = try YAMLDecoder().decode(
            SpriteConfig.self,
            from: Data("""
            root: Sprites/Player
            chroma: black
            """.utf8)
        )
        #expect(black.chromaKey == "#000000")
        #expect(black.chromaKeyTolerance == 0)

        let soft = try YAMLDecoder().decode(
            SpriteConfig.self,
            from: Data("""
            root: Sprites/UI/Levels
            chroma: black_soft
            """.utf8)
        )
        #expect(soft.chromaKey == "#000000")
        #expect(soft.chromaKeyTolerance == 2)

        let item = try YAMLDecoder().decode(
            SpriteConfig.self,
            from: Data("""
            root: Sprites/Effects/Explosion
            chroma: white_item
            """.utf8)
        )
        #expect(item.chromaKey == "#FFFFFF")
        #expect(item.chromaKeyTolerance == 12)
        #expect(item.chromaKeyFeather == 20)
        #expect(item.chromaKeySmooth == 2)

        let overridden = try YAMLDecoder().decode(
            SpriteConfig.self,
            from: Data("""
            root: Sprites/Player
            chroma: black
            chroma_key_tolerance: 5
            """.utf8)
        )
        #expect(overridden.chromaKey == "#000000")
        #expect(overridden.chromaKeyTolerance == 5)
    }

    /// Normalized RGBA8 top-left pixel buffer for exact image comparisons.
    private func rgbaBytes(
        of image: CGImage,
        flipVertically: Bool = false,
        crop: CGRect? = nil
    ) -> [UInt8]? {
        let source: CGImage
        if let crop {
            guard let cropped = image.cropping(to: crop) else { return nil }
            source = cropped
        } else {
            source = image
        }
        let width = source.width
        let height = source.height
        guard width > 0, height > 0 else { return nil }
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var data = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        if flipVertically {
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        } else {
            // Match SpriteSheetLoader / CGImage.cropping top-left space.
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return data
    }
}
