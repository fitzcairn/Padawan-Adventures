import CoreGraphics
import Foundation
import SpriteKit
import Testing
@testable import Padawan_Adventures

struct FloorSpriteSystemTests {
    @Test func floorAtlasComputesEvenCellOrigins() {
        #expect(FloorAtlas.dividedOrigin(0, total: 352, count: 11) == 0)
        #expect(FloorAtlas.dividedOrigin(11, total: 352, count: 11) == 352)
        // 352/11 = 32 exactly.
        let width0 = FloorAtlas.dividedOrigin(1, total: 352, count: 11)
            - FloorAtlas.dividedOrigin(0, total: 352, count: 11)
        #expect(width0 == 32)
    }

    @Test func floorAtlasFrameRectsCoverSingleFrameGrid() throws {
        let json = """
        {
          "meta": {
            "size": { "w": 2048, "h": 2048 },
            "duration_s": 1.0,
            "blocks": { "cols": 1, "rows": 1, "width": 2048, "height": 2048 },
            "grid": { "cols": 11, "rows": 11 }
          }
        }
        """
        let atlas = try FloorAtlas.decode(from: Data(json.utf8))
        #expect(atlas.frameCount == 1)
        #expect(abs(atlas.frameDurationSeconds() - 1.0) < 0.000_1)

        let first = try #require(atlas.frameRect(tileRow: 0, tileCol: 0, frameIndex: 0))
        let cell = CGFloat(FloorAtlas.dividedOrigin(1, total: 2048, count: 11))
        #expect(first == CGRect(x: 0, y: 0, width: cell, height: cell))

        let last = try #require(atlas.frameRect(tileRow: 10, tileCol: 10, frameIndex: 0))
        #expect(last.maxX == 2048)
        #expect(last.maxY == 2048)
    }

    @Test func terrainCatalogDecodesSpriteBlockAndNearby() throws {
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
        terrains:
          water:
            row: 9
            col: 0
            nearby: [water-clear, water-shallow]
          water-clear:
            row: 9
            col: 1
            nearby: [water]
        """
        let catalog = try TerrainCatalog.decode(from: Data(yaml.utf8))
        #expect(catalog.sprite.root == "Sprites/Floor")
        #expect(catalog.sprite.atlasRoot == "Sprites/Floor")
        #expect(catalog.sprite.chromaKey == "#FFFFFF")
        #expect(catalog.sprite.chromaKeyTolerance == 18)
        #expect(catalog.sprite.chromaKeyFeather == 48)
        #expect(catalog.sprite.chromaKeySmooth == 2)
        #expect(catalog.terrains["water"]?.row == 9)
        #expect(catalog.terrains["water"]?.nearby == ["water-clear", "water-shallow"])
        #expect(catalog.nearbyByID["water-clear"] == ["water"])
    }

    @Test func bundleTerrainCatalogLoadsWithExpectedCount() throws {
        let catalog = try TerrainCatalog.loadFromBundle()
        #expect(catalog.terrains.count == 115)
        #expect(catalog.sprite.chromaKey == "#FFFFFF")
        #expect(catalog.sprite.chromaKeyTolerance == 18)
        #expect(catalog.sprite.chromaKeyFeather == 48)
        #expect(catalog.sprite.chromaKeySmooth == 2)
        #expect(catalog.terrains["water"] != nil)
        #expect(catalog.terrains["grass"] != nil)
        #expect(catalog.terrains["sand"] != nil)
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

    @Test func floorTerrainAssignmentUsesNearbyIntersection() throws {
        var tiles: [[[Tile]]] = [
            [
                [Tile(kind: .floor(isPit: false)), Tile(kind: .floor(isPit: false))],
                [Tile(kind: .wall(destructible: false)), Tile(kind: .floor(isPit: true))],
            ],
        ]
        let palette = ["a", "b", "c"]
        let nearby: [String: [String]] = [
            "a": ["b"],
            "b": ["c"],
            "c": ["a"],
        ]
        var rng = SeededGenerator(seed: 42)
        // Use the same algorithm as ProceduralGenerator via a tiny local copy for determinism checks:
        // first floor picks from palette; subsequent from intersection.
        var previous: String?
        for y in tiles[0].indices {
            for x in tiles[0][y].indices {
                guard case .floor = tiles[0][y][x].kind else { continue }
                let candidates: [String]
                if let previous, let near = nearby[previous] {
                    let intersection = near.filter { palette.contains($0) }
                    candidates = intersection.isEmpty ? palette : intersection
                } else {
                    candidates = palette
                }
                let pick = candidates[Int.random(in: 0..<candidates.count, using: &rng)]
                tiles[0][y][x].terrainID = pick
                previous = pick
            }
        }

        let ids = tiles[0].flatMap { $0.compactMap(\.terrainID) }
        #expect(ids.count == 3)
        #expect(Set(ids).isSubset(of: Set(palette)))
        // With nearby a→b→c→a, consecutive floor picks (scan order) stay in the chain.
        if ids.count >= 2 {
            let first = ids[0]
            let second = ids[1]
            #expect(nearby[first]?.contains(second) == true || first == second)
        }
    }

    @Test func tilePersistsTerrainID() throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let decoder = PropertyListDecoder()

        let tile = Tile(kind: .floor(isPit: false), terrainID: "grass")
        let data = try encoder.encode(tile)
        let decoded = try decoder.decode(Tile.self, from: data)
        #expect(decoded.terrainID == "grass")
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
    }

    @Test func proceduralGeneratorAssignsFloorTerrains() throws {
        var config = WorldSeedConfig(
            version: 1,
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
            extensions: nil,
            floorSprites: ["grass", "dirt-arid", "sand"]
        )
        config.enemies = .init(types: ["horranth"], spawnChancePerRoom: 1.0)
        let nearby: [String: [String]] = [
            "grass": ["dirt-arid", "sand"],
            "dirt-arid": ["grass", "sand"],
            "sand": ["grass", "dirt-arid"],
        ]
        let world = try ProceduralGenerator().generate(
            from: config,
            terrainNearby: nearby
        )
        var floorCount = 0
        var assigned = 0
        for story in world.tiles {
            for row in story {
                for tile in row {
                    guard case .floor = tile.kind else { continue }
                    floorCount += 1
                    if let id = tile.terrainID {
                        assigned += 1
                        #expect(["grass", "dirt-arid", "sand"].contains(id))
                    }
                }
            }
        }
        #expect(floorCount > 0)
        #expect(assigned == floorCount)
    }

    @Test func floorSpriteLoaderSlicesSampleTerrainFromBundle() throws {
        let catalog = try TerrainCatalog.loadFromBundle()
        // Load only via a one-entry catalog so the test stays fast.
        let sampleID = "water"
        let sample = try #require(catalog.terrains[sampleID])
        let slim = TerrainCatalog(
            sprite: catalog.sprite,
            terrains: [sampleID: sample]
        )
        let animations = try FloorSpriteLoader.loadAll(catalog: slim)
        let animation = try #require(animations[sampleID])
        #expect(animation.frames.count == 1)
        #expect(abs(animation.frames.map(\.duration).reduce(0, +) - 1.0) < 0.001)
        let size = animation.frames[0].texture.size()
        #expect(size.width > 1)
        #expect(size.height > 1)
    }

    @Test @MainActor
    func floorSpriteLibraryLoadsAllTerrainsFromBundle() throws {
        let catalog = try TerrainCatalog.loadFromBundle()
        let library = FloorSpriteLibrary()
        library.ensureLoaded(catalog: catalog)
        #expect(library.animationCount == catalog.terrains.count)
        #expect(library.animationCount > 0)
    }
}
