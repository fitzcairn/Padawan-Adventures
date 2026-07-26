import CoreGraphics
import Foundation
import SpriteKit
import Testing
import UIKit
@testable import Padawan_Adventures

/// Golden-image snapshots of frame-0 textures after the real AnimatedSpriteNode path.
///
/// Goldens live under `Padawan AdventuresTests/Fixtures/`. If a golden is missing,
/// the test writes it and fails with "re-run" so the next run compares.
@MainActor
struct SpriteOrientationSnapshotTests {
    private static let perChannelTolerance = 2

    @Test
    func playerIdleDownFrame0MatchesGolden() async throws {
        let player = try PlayerConfig.loadFromBundle()
        var spriteConfig = try #require(player.sprite)
        let idleSource = try #require(spriteConfig.animations["idle_down"])
        spriteConfig.animations = ["idle_down": idleSource]

        let library = SpriteLibrary()
        await library.ensureLoaded(spriteConfig, id: "player")
        #expect(library.animation(named: "idle_down") != nil)

        let iso = IsometricConfig()
        let container = PlaceholderFactory.playerSpriteNode(
            config: iso,
            library: library,
            spriteConfig: spriteConfig
        )
        let sprite = try #require(
            container.childNode(withName: AnimatedSpriteNode.nodeName) as? AnimatedSpriteNode
        )
        #expect(sprite.correctsUIImageVInversion == true)
        #expect(sprite.anchorPoint.y == 1)
        #expect(sprite.currentAnimationName == "idle_down")

        try assertTextureMatchesGolden(sprite.texture, named: "player-idle_down-frame0.png")
    }

    @Test
    func floorTileMatchesGolden() async throws {
        let library = FloorTileSetLibrary()
        await library.ensureLoaded(set: "1-tython")
        let set = try #require(library.tileSet)
        let tileID = try #require(set.floorTileIDs.first)
        let texture = try #require(library.texture(tileID))
        let frame = try #require(library.frame(tileID))

        let container = PlaceholderFactory.floorTileNode(
            tileID: tileID,
            texture: texture,
            frame: frame,
            diamond: set.meta.diamond,
            config: IsometricConfig(tileWidth: 80, tileHeight: 49)
        )
        let sprite = try #require(container.children.first as? SKSpriteNode)
        #expect(sprite.texture != nil)

        try assertTextureMatchesGolden(sprite.texture, named: "floor-tython-r00c00.png")
    }

    @Test
    func enemyIdleRightFrame0MatchesGolden() async throws {
        let enemies = try EnemyConfig.loadFromBundle()
        let (libraryID, fullConfig) = try #require(Self.enemySpriteWithIdleRight(from: enemies))
        var spriteConfig = fullConfig
        let idleRight = try #require(spriteConfig.animations["idle_right"])
        spriteConfig.animations = ["idle_right": idleRight]

        let library = SpriteLibrary()
        await library.ensureLoaded(spriteConfig, id: libraryID)
        #expect(library.animation(id: libraryID, named: "idle_right") != nil)

        let iso = IsometricConfig()
        let container = PlaceholderFactory.enemySpriteNode(
            entityID: UUID(),
            config: iso,
            library: library,
            spriteConfig: spriteConfig,
            libraryID: libraryID
        )
        let sprite = try #require(
            container.childNode(withName: AnimatedSpriteNode.nodeName) as? AnimatedSpriteNode
        )
        // Factory starts on idle_down; switch to the facing under test.
        sprite.play(name: "idle_right", library: library, libraryID: libraryID)
        #expect(sprite.correctsUIImageVInversion == true)
        #expect(sprite.anchorPoint.y == 1)
        #expect(sprite.currentAnimationName == "idle_right")

        try assertTextureMatchesGolden(
            sprite.texture,
            named: "enemy-\(libraryID)-idle_right-frame0.png"
        )
    }

    // MARK: - Helpers

    private static func fixturesDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Sprites
            .deletingLastPathComponent() // Game
            .deletingLastPathComponent() // Padawan AdventuresTests
            .appendingPathComponent("Fixtures")
    }

    /// Prefers `dino` when it has `idle_right`; otherwise the first sprite that does.
    private static func enemySpriteWithIdleRight(
        from config: EnemyConfig
    ) -> (id: String, config: SpriteConfig)? {
        if let dino = config.sprites["dino"], dino.animations["idle_right"] != nil {
            return ("dino", dino)
        }
        for id in config.sprites.keys.sorted() {
            if let sprite = config.sprites[id], sprite.animations["idle_right"] != nil {
                return (id, sprite)
            }
        }
        return nil
    }

    private func assertTextureMatchesGolden(_ texture: SKTexture?, named fileName: String) throws {
        let texture = try #require(texture)
        let actualImage = texture.cgImage()
        let actual = try #require(Self.rgbaBytes(of: actualImage))
        let width = actualImage.width
        let height = actualImage.height
        #expect(width > 0)
        #expect(height > 0)

        let fixtures = Self.fixturesDirectory()
        let goldenURL = fixtures.appendingPathComponent(fileName)
        if !FileManager.default.fileExists(atPath: goldenURL.path) {
            try FileManager.default.createDirectory(
                at: fixtures,
                withIntermediateDirectories: true
            )
            try Self.writePNG(image: actualImage, to: goldenURL)
            #expect(Bool(false), "Wrote golden at \(goldenURL.path); re-run test")
            return
        }

        let goldenData = try Data(contentsOf: goldenURL)
        let goldenUIImage = try #require(UIImage(data: goldenData))
        let goldenCGImage = try #require(goldenUIImage.cgImage)
        let expected = try #require(Self.rgbaBytes(of: goldenCGImage))

        #expect(goldenCGImage.width == width)
        #expect(goldenCGImage.height == height)
        #expect(expected.count == actual.count)

        let mismatch = Self.firstChannelMismatch(
            actual: actual,
            expected: expected,
            tolerance: Self.perChannelTolerance
        )
        if let mismatch {
            let message =
                "RGBA mismatch vs \(fileName) at byte \(mismatch.offset): "
                + "actual=\(mismatch.actual) expected=\(mismatch.expected) "
                + "(tolerance ±\(Self.perChannelTolerance))"
            Issue.record("\(message)")
        }
        #expect(mismatch == nil)
    }

    private static func rgbaBytes(of image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        let bytesPerRow = width * 4
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
        // Match SpriteSystemTests / CGImage top-left space.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return data
    }

    private static func writePNG(image: CGImage, to url: URL) throws {
        let uiImage = UIImage(cgImage: image)
        guard let png = uiImage.pngData() else {
            throw SnapshotError.failedToEncodePNG(url.path)
        }
        try png.write(to: url)
    }

    private static func firstChannelMismatch(
        actual: [UInt8],
        expected: [UInt8],
        tolerance: Int
    ) -> (offset: Int, actual: UInt8, expected: UInt8)? {
        let count = min(actual.count, expected.count)
        for index in 0..<count {
            let delta = abs(Int(actual[index]) - Int(expected[index]))
            if delta > tolerance {
                return (index, actual[index], expected[index])
            }
        }
        if actual.count != expected.count {
            return (count, 0, 0)
        }
        return nil
    }

    private enum SnapshotError: Error {
        case failedToEncodePNG(String)
    }
}
