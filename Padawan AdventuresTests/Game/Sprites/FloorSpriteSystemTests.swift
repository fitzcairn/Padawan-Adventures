import CoreGraphics
import Foundation
import SpriteKit
import Testing
@testable import Padawan_Adventures

struct FloorSpriteSystemTests {
    @Test func floorAtlasDecodesNamedFrames() throws {
        let json = """
        {
          "meta": {
            "size": { "w": 2046, "h": 2046 },
            "duration_s": 0
          },
          "frames": {
            "sand": { "x": 0, "y": 41, "w": 186, "h": 145 },
            "flowers": { "x": 31, "y": 744, "w": 136, "h": 166 }
          }
        }
        """
        let atlas = try FloorAtlas.decode(from: Data(json.utf8))
        #expect(atlas.meta.size.w == 2046)
        #expect(atlas.frames.count == 2)
        let sand = try #require(atlas.frameRect(named: "sand"))
        #expect(sand == CGRect(x: 0, y: 41, width: 186, height: 145))
        let flowers = try #require(atlas.frameRect(named: "flowers"))
        #expect(flowers.width < 186)
        #expect(flowers.height < 186)
        #expect(atlas.frameRect(named: "missing") == nil)
    }

    @Test func bundleFloorAtlasListsEveryTerrain() throws {
        let catalog = try TerrainCatalog.loadFromBundle()
        guard let url = Bundle.main.url(
            forResource: "atlas",
            withExtension: "json",
            subdirectory: "Sprites/Floor"
        ) ?? Bundle.main.url(forResource: "atlas", withExtension: "json") else {
            Issue.record("Missing floor atlas.json in bundle")
            return
        }
        let atlas = try FloorAtlas.decode(from: Data(contentsOf: url))
        #expect(atlas.frames.count == catalog.terrains.count)
        for id in catalog.terrains.keys {
            let rect = try #require(atlas.frameRect(named: id))
            #expect(rect.width >= 1)
            #expect(rect.height >= 1)
            #expect(rect.maxX <= CGFloat(atlas.meta.size.w) + 0.5)
            #expect(rect.maxY <= CGFloat(atlas.meta.size.h) + 0.5)
        }
    }

    @Test func terrainCatalogDecodesTypeAccentsAndSpecials() throws {
        let yaml = """
        sprite:
          root: Sprites/Floor
          sheet: floor-spritesheet
          atlas_root: Sprites/Floor
          atlas: atlas
          chroma_key: "#FFFFFF"
          chroma_key_tolerance: 18
          chroma_key_feather: 48
          chroma_key_smooth: 2
        palettes:
          grassland:
            accents: [flowers, stump]
            specials: [foliage]
        terrains:
          grass: { row: 2, col: 0, palette: grassland }
          flowers: { row: 4, col: 0, type: accent }
          foliage: { row: 3, col: 0, type: special }
        """
        let catalog = try TerrainCatalog.decode(from: Data(yaml.utf8))
        #expect(catalog.sprite.root == "Sprites/Floor")
        #expect(catalog.sprite.atlasRoot == "Sprites/Floor")
        #expect(catalog.sprite.chromaKey == "#FFFFFF")
        #expect(catalog.sprite.chromaKeyTolerance == 18)
        #expect(catalog.sprite.chromaKeyFeather == 48)
        #expect(catalog.sprite.chromaKeySmooth == 2)
        #expect(catalog.terrains["grass"]?.type == .base)
        #expect(catalog.terrains["grass"]?.accents == ["flowers", "stump"])
        #expect(catalog.terrains["grass"]?.specials == ["foliage"])
        #expect(catalog.terrains["flowers"]?.type == .accent)
        #expect(catalog.terrains["foliage"]?.type == .special)
        #expect(catalog.accents(for: "grass") == ["flowers", "stump"])
        #expect(catalog.specials(for: "grass") == ["foliage"])
        #expect(catalog.type(of: "flowers") == .accent)
    }

    @Test func bundleTerrainCatalogLoadsWithExpectedCount() throws {
        let catalog = try TerrainCatalog.loadFromBundle()
        #expect(catalog.terrains.count == 115)
        #expect(catalog.sprite.chromaKey == "#FFFFFF")
        #expect(catalog.sprite.chromaKeyTolerance == 18)
        #expect(catalog.sprite.chromaKeyFeather == 48)
        #expect(catalog.sprite.chromaKeySmooth == 2)
        #expect(catalog.terrains["water"]?.type == .base)
        #expect(catalog.terrains["grass"]?.type == .base)
        #expect(catalog.terrains["sand"]?.type == .base)
        #expect(catalog.terrains["swamp-roots"]?.type == .special)
        #expect(catalog.terrains["flowers"]?.type == .accent)
        #expect(catalog.terrains["mushroom"]?.type == .special)
        #expect(catalog.specials(for: "swamp").contains("swamp-roots"))
        #expect(catalog.specials(for: "grass").contains("foliage"))
    }

    @Test func chromaKeyToleranceRemovesNearBlack() throws {
        // 2x1: near-black (0,1,0) and solid red.
        let width = 2
        let height = 1
        var pixels: [UInt8] = [
            0, 1, 0, 255,
            255, 0, 0, 255,
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

        let exact = SpriteSheetLoader.applyChromaKey(
            to: image,
            key: (0, 0, 0),
            tolerance: 0
        )
        // Exact key leaves near-black opaque.
        #expect(SpriteSheetLoader.opaqueContentBounds(of: exact)?.width == 2)

        let tolerant = SpriteSheetLoader.applyChromaKey(
            to: image,
            key: (0, 0, 0),
            tolerance: 8
        )
        let bounds = try #require(SpriteSheetLoader.opaqueContentBounds(of: tolerant))
        #expect(bounds.width == 1)
        #expect(bounds.minX == 1)
    }

    @Test func chromaKeyFeatherSoftensNearKeyFringe() throws {
        // 3x1: exact white key | mid-feather near-white | solid red.
        // Distance 35 sits between tolerance 18 and tolerance+feather 66.
        let width = 3
        let height = 1
        var pixels: [UInt8] = [
            255, 255, 255, 255,
            220, 220, 220, 255,
            255, 0, 0, 255,
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

        let keyed = SpriteSheetLoader.applyChromaKey(
            to: image,
            key: (255, 255, 255),
            tolerance: 18,
            feather: 48,
            smoothRadius: 0
        )
        // Hard key gone; fringe partially transparent; red intact.
        let keyAlpha = try #require(pixelAlpha(of: keyed, x: 0))
        let fringeAlpha = try #require(pixelAlpha(of: keyed, x: 1))
        let redAlpha = try #require(pixelAlpha(of: keyed, x: 2))
        #expect(keyAlpha == 0)
        #expect(fringeAlpha > 0 && fringeAlpha < 255)
        #expect(redAlpha == 255)
    }

    @Test func chromaKeySmoothBlursAlphaEdge() throws {
        // Opaque red next to fully keyed white — smooth should bleed alpha into the key side.
        let width = 3
        let height = 1
        var pixels: [UInt8] = [
            255, 255, 255, 255,
            255, 0, 0, 255,
            255, 0, 0, 255,
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

        let keyed = SpriteSheetLoader.applyChromaKey(
            to: image,
            key: (255, 255, 255),
            tolerance: 0,
            feather: 0,
            smoothRadius: 1
        )
        let edgeAlpha = try #require(pixelAlpha(of: keyed, x: 0))
        #expect(edgeAlpha > 0 && edgeAlpha < 255)
    }

    private func pixelAlpha(of image: CGImage, x: Int) -> UInt8? {
        guard let cropped = image.cropping(to: CGRect(x: x, y: 0, width: 1, height: 1)) else {
            return nil
        }
        var data = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &data,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.translateBy(x: 0, y: 1)
        context.scaleBy(x: 1, y: -1)
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return data[3]
    }

    @Test func tilePersistsTerrainAndAccentIDs() throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let decoder = PropertyListDecoder()

        let tile = Tile(
            kind: .floor(isPit: false),
            terrainID: "grass",
            accentTerrainID: "flowers"
        )
        let data = try encoder.encode(tile)
        let decoded = try decoder.decode(Tile.self, from: data)
        #expect(decoded.terrainID == "grass")
        #expect(decoded.accentTerrainID == "flowers")
        if case .floor(let isPit) = decoded.kind {
            #expect(!isPit)
        } else {
            Issue.record("Expected floor kind")
        }
    }

    @Test func legacyTileWithoutTerrainIDDecodes() throws {
        let json = """
        {"kind":{"type":"floor","isPit":false}}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Tile.self, from: json)
        #expect(decoded.terrainID == nil)
        #expect(decoded.accentTerrainID == nil)
    }

    @Test func floorIdentitySeparatesBaseAndAccent() {
        let withAccent = Tile(
            kind: .floor(isPit: false),
            terrainID: "grass",
            accentTerrainID: "flowers"
        )
        let withoutAccent = Tile(kind: .floor(isPit: false), terrainID: "grass")
        #expect(PlaceholderFactory.floorIdentity(for: withAccent) == "grass|0")
        #expect(PlaceholderFactory.floorIdentity(for: withoutAccent) == "grass|0")
        #expect(PlaceholderFactory.floorAccentIdentity(for: withAccent) == "flowers")
        #expect(PlaceholderFactory.floorAccentIdentity(for: withoutAccent) == nil)
    }

    @Test func proceduralGeneratorAssignsFloorTerrainsWithAccentsAndSpecials() throws {
        var config = WorldGenerationConfig(
            seed: 7,
            world: .init(width: 30, height: 30, stories: 1),
            generation: .init(
                algorithm: "rooms_doors",
                roomCount: 5,
                corridorWidth: 2,
                room: .init(
                    minRoomSize: 4,
                    maxRoomSize: 10,
                    pitChance: 0.2,
                    wallDestructibleChance: 0.3,
                    gateChance: 0.5
                )
            ),
            floorSprites: ["grass"],
            floorAccentProb: 1.0,
            cornerSpecialProb: 1.0
        )
        config.enemies = .init(types: ["horranth"], spawnChancePerRoom: 1.0)
        let placement = TerrainPlacementTable(
            accents: ["grass": ["flowers"]],
            specials: ["grass": ["foliage"]]
        )
        let world = try ProceduralGenerator().generate(
            from: config,
            terrainPlacement: placement
        )
        var floorCount = 0
        var specialCount = 0
        var accentCount = 0
        let story = world.tiles[0]
        let height = story.count
        let width = story.first?.count ?? 0
        for y in 0..<height {
            for x in 0..<width {
                let tile = story[y][x]
                guard case .floor = tile.kind else { continue }
                floorCount += 1
                let id = try #require(tile.terrainID)
                #expect(id == "grass" || id == "foliage")
                if id == "foliage" {
                    specialCount += 1
                    #expect(tile.accentTerrainID == nil)
                } else if let accent = tile.accentTerrainID {
                    accentCount += 1
                    #expect(accent == "flowers")
                    for (dx, dy) in [(0, -1), (1, 0), (0, 1), (-1, 0)] {
                        let nx = x + dx
                        let ny = y + dy
                        guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                        #expect(story[ny][nx].accentTerrainID == nil)
                    }
                }
            }
        }
        #expect(floorCount > 0)
        #expect(specialCount > 0)
        #expect(accentCount > 0)
    }

    @Test func levelConfigFallbackFloorSpritesAreBaseOnly() {
        #expect(!LevelConfig.fallbackFloorSprites.contains("foliage"))
        #expect(LevelConfig.fallbackFloorSprites.contains("grass"))
        #expect(LevelConfig.fallbackFloorAccentProb == 0.15)
        #expect(LevelConfig.fallbackCornerSpecialProb == 0.15)
    }

    @Test func floorSpriteLoaderSlicesSampleTerrainFromBundle() async throws {
        let catalog = try TerrainCatalog.loadFromBundle()
        // Load only via a one-entry catalog so the test stays fast.
        let sampleID = "water"
        let sample = try #require(catalog.terrains[sampleID])
        let slim = TerrainCatalog(
            sprite: catalog.sprite,
            terrains: [sampleID: sample]
        )
        let animations = try await FloorSpriteLoader.loadAll(catalog: slim)
        let animation = try #require(animations[sampleID])
        #expect(animation.frames.count == 1)
        #expect(animation.frames[0].duration == 0)
        let size = animation.frames[0].texture.size()
        #expect(size.width > 1)
        #expect(size.height > 1)
    }

    @Test @MainActor
    func floorSpritePlayDoesNotStartLoopingAction() {
        let texture = SKTexture()
        let animation = SpriteAnimation(frames: [
            SpriteFrame(texture: texture, duration: 0),
        ])
        let sprite = AnimatedSpriteNode(size: CGSize(width: 40, height: 40))
        sprite.play(animation: animation, name: "grass")
        #expect(sprite.action(forKey: AnimatedSpriteNode.animationActionKey) == nil)
        #expect(sprite.currentAnimationName == "grass")
    }

    @Test @MainActor
    func floorSpriteLibraryLoadsAllTerrainsFromBundle() async throws {
        let catalog = try TerrainCatalog.loadFromBundle()
        let library = FloorSpriteLibrary()
        await library.ensureLoaded(catalog: catalog)
        #expect(library.animationCount == catalog.terrains.count)
        #expect(library.animationCount > 0)
    }
}
