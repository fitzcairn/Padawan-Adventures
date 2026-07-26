import CoreGraphics
import SpriteKit
import Testing
@testable import Padawan_Adventures

struct PlaceholderFactoryTests {
    @Test func floorTileUsesHorizontalEdges() {
        let config = IsometricConfig(tileWidth: 64, tileHeight: 32, wallHeight: 48)
        let floor = PlaceholderFactory.horizontalFloorNode(isPit: false, config: config)
        let bounds = floor.path?.boundingBox ?? .zero

        #expect(bounds.width > 0)
        #expect(bounds.height > 0)
        #expect(abs(bounds.maxY - bounds.minY) > abs(bounds.maxX - bounds.minX) * 0.1)
    }

    @Test func wallTileIsTallerThanFloor() {
        let config = IsometricConfig(tileWidth: 64, tileHeight: 32, wallHeight: 48)
        let floor = PlaceholderFactory.horizontalFloorNode(isPit: false, config: config)
        let wall = PlaceholderFactory.perspectiveWallNode(faces: .all, config: config)
        let floorBounds = floor.path?.boundingBox ?? .zero
        let wallBounds = wall.calculateAccumulatedFrame()

        #expect(wallBounds.height > floorBounds.height)
    }

    @Test func leftWallFaceSlantsAlongWestSouthEdge() {
        let config = IsometricConfig(tileWidth: 64, tileHeight: 32, wallHeight: 48)
        let path = IsometricTileGeometry.leftWallFacePath(config: config)
        let bounds = path.boundingBox

        #expect(bounds.minX < 0)
        #expect(bounds.maxX <= 0.001)
        #expect(bounds.height > config.tileHeight)
    }

    @Test func rightWallFaceSlantsAlongEastSouthEdge() {
        let config = IsometricConfig(tileWidth: 64, tileHeight: 32, wallHeight: 48)
        let path = IsometricTileGeometry.rightWallFacePath(config: config)
        let bounds = path.boundingBox

        #expect(bounds.maxX > 0)
        #expect(bounds.minX >= -0.001)
        #expect(bounds.height > config.tileHeight)
    }

    @Test func wallFacesAreNotAxisAlignedRectangles() {
        let config = IsometricConfig(tileWidth: 64, tileHeight: 32, wallHeight: 48)
        let left = IsometricTileGeometry.leftWallFacePath(config: config).boundingBox
        let right = IsometricTileGeometry.rightWallFacePath(config: config).boundingBox

        // Perspective faces are parallelograms: width is half-tile, not full tileWidth.
        #expect(left.width < config.tileWidth)
        #expect(right.width < config.tileWidth)
        #expect(abs(left.width - config.tileWidth / 2) < 0.001)
        #expect(abs(right.width - config.tileWidth / 2) < 0.001)
    }

    @Test func opaqueNeighborCullsSharedWallFace() {
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        let a = GridCoord(x: 1, y: 1, story: 0)
        let east = GridCoord(x: 2, y: 1, story: 0)
        let south = GridCoord(x: 1, y: 2, story: 0)

        world.setTile(Tile(kind: .wall), at: a)
        world.setTile(Tile(kind: .wall), at: east)
        world.setTile(Tile(kind: .wall), at: south)

        let faces = IsometricTileGeometry.visibleFaces(at: a, in: world)
        #expect(!faces.contains(.right))
        #expect(!faces.contains(.left))
        #expect(faces.contains(.top))
    }

    @Test func openNeighborKeepsPerspectiveFace() {
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        let a = GridCoord(x: 1, y: 1, story: 0)
        world.setTile(Tile(kind: .wall), at: a)

        let faces = IsometricTileGeometry.visibleFaces(at: a, in: world)
        #expect(faces.contains(.left))
        #expect(faces.contains(.right))
    }

    @Test func floorIsWhiteAndPitIsDarkBrown() {
        let config = IsometricConfig()
        let floor = PlaceholderFactory.tileNode(
            for: Tile(kind: .floor(isPit: false)),
            at: GridCoord(x: 0, y: 0, story: 0),
            config: config
        )
        let pit = PlaceholderFactory.tileNode(
            for: Tile(kind: .floor(isPit: true)),
            at: GridCoord(x: 0, y: 0, story: 0),
            config: config
        )

        let floorShape = floor.children.first as? SKShapeNode
        let pitShape = pit.children.first as? SKShapeNode
        #expect(colorsMatch(floorShape?.fillColor, PlaceholderFactory.floorColor))
        #expect(colorsMatch(pitShape?.fillColor, PlaceholderFactory.pitColor))
    }

    @Test func pitTileDropsBelowNeighbouringFloor() {
        let config = IsometricConfig(tileWidth: 80, tileHeight: 49)
        let coord = GridCoord(x: 2, y: 1, story: 0)
        let floor = PlaceholderFactory.tileNode(
            for: Tile(kind: .floor(isPit: false)),
            at: coord,
            config: config
        )
        let pit = PlaceholderFactory.tileNode(
            for: Tile(kind: .floor(isPit: true)),
            at: coord,
            config: config
        )
        #expect(abs(floor.position.x - pit.position.x) < 0.001)
        #expect(
            abs(floor.position.y - pit.position.y - PlaceholderFactory.pitDropPixels) < 0.001
        )
    }

    @Test @MainActor
    func floorTileNodeAnchorsNorthCornerAndScalesToDiamond() async throws {
        let library = FloorTileSetLibrary()
        await library.ensureLoaded(set: "1-tython")
        let set = try #require(library.tileSet)
        let tid = try #require(set.floorTileIDs.first)
        let frame = try #require(set.frames[tid])
        let texture = try #require(library.texture(tid))
        let config = IsometricConfig(tileWidth: 80, tileHeight: 49)
        let node = PlaceholderFactory.floorTileNode(
            tileID: tid,
            texture: texture,
            frame: frame,
            diamond: set.meta.diamond,
            config: config
        )
        let sprite = try #require(node.children.first as? SKSpriteNode)
        let sx = config.tileWidth / set.meta.diamond.w
        let sy = config.tileHeight / set.meta.diamond.h
        #expect(abs(sprite.size.width - CGFloat(frame.w) * sx) < 0.001)
        #expect(abs(sprite.size.height - CGFloat(frame.h) * sy) < 0.001)
        #expect(abs(sprite.anchorPoint.x - frame.anchor.x / CGFloat(frame.w)) < 0.001)
        #expect(abs(sprite.anchorPoint.y - (1 - frame.anchor.y / CGFloat(frame.h))) < 0.001)
        #expect(sprite.position == .zero)
    }

    private func colorsMatch(_ actual: UIColor?, _ expected: UIColor) -> Bool {
        guard let actual else { return false }
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var er: CGFloat = 0, eg: CGFloat = 0, eb: CGFloat = 0, ea: CGFloat = 0
        guard actual.getRed(&ar, green: &ag, blue: &ab, alpha: &aa),
              expected.getRed(&er, green: &eg, blue: &eb, alpha: &ea)
        else { return false }
        return abs(ar - er) < 0.001 && abs(ag - eg) < 0.001
            && abs(ab - eb) < 0.001 && abs(aa - ea) < 0.001
    }

    @Test func spellingGateUsesGreenColor() {
        let config = IsometricConfig()
        let node = PlaceholderFactory.tileNode(
            for: Tile(kind: .gate(minigame: .spelling)),
            at: GridCoord(x: 0, y: 0, story: 0),
            config: config
        )
        let faces = node.children.first?.children.compactMap { $0 as? SKShapeNode } ?? []
        #expect(!faces.isEmpty)
        var sawGreenFamily = false
        for face in faces {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            if face.fillColor.getRed(&r, green: &g, blue: &b, alpha: &a), g > r, g > 0.5 {
                sawGreenFamily = true
            }
        }
        #expect(sawGreenFamily)
    }

    @Test func letterMatchGateUsesLightBlueColor() {
        let config = IsometricConfig()
        let node = PlaceholderFactory.tileNode(
            for: Tile(kind: .gate(minigame: .letterMatch)),
            at: GridCoord(x: 0, y: 0, story: 0),
            config: config
        )
        let faces = node.children.first?.children.compactMap { $0 as? SKShapeNode } ?? []
        #expect(!faces.isEmpty)
        var sawBlueFamily = false
        for face in faces {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            if face.fillColor.getRed(&r, green: &g, blue: &b, alpha: &a), b > r, b > 0.5 {
                sawBlueFamily = true
            }
        }
        #expect(sawBlueFamily)
    }

    @Test func drawnPitDoesNotNeedCeiling() {
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        let west = GridCoord(x: 0, y: 1, story: 0)
        let pit = GridCoord(x: 1, y: 1, story: 0)
        let east = GridCoord(x: 2, y: 1, story: 0)
        world.setTile(Tile(kind: .wall), at: west)
        world.setTile(Tile(kind: .floor(isPit: true)), at: pit)
        world.setTile(Tile(kind: .wall), at: east)

        #expect(!IsometricTileGeometry.needsCeiling(at: pit, in: world))
        #expect(!IsometricTileGeometry.needsCeiling(at: GridCoord(x: 1, y: 0, story: 0), in: world))
    }

    @Test func openFloorDoesNotNeedCeiling() {
        let world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        #expect(!IsometricTileGeometry.needsCeiling(at: GridCoord(x: 1, y: 1, story: 0), in: world))
    }

    @Test func unrenderedInteriorWallNeedsCeiling() {
        // 3×3 solid walls: center has no walkable neighbor → no wall block, but ceiling.
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        for y in 0..<3 {
            for x in 0..<3 {
                world.setTile(
                    Tile(kind: .wall),
                    at: GridCoord(x: x, y: y, story: 0)
                )
            }
        }
        let center = GridCoord(x: 1, y: 1, story: 0)
        #expect(!IsometricTileGeometry.shouldRenderWall(at: center, in: world))
        #expect(IsometricTileGeometry.needsCeiling(at: center, in: world))
    }

    @Test func renderedWallBorderingFloorDoesNotNeedCeiling() {
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        let wall = GridCoord(x: 1, y: 1, story: 0)
        world.setTile(Tile(kind: .wall), at: wall)
        #expect(IsometricTileGeometry.shouldRenderWall(at: wall, in: world))
        #expect(!IsometricTileGeometry.needsCeiling(at: wall, in: world))
    }

    @Test func wallIdentityTracksKindAndFaces() {
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        let a = GridCoord(x: 1, y: 1, story: 0)
        world.setTile(Tile(kind: .gate(minigame: .spelling)), at: a)

        let solid = PlaceholderFactory.wallIdentity(
            for: Tile(kind: .wall),
            at: a,
            in: world
        )
        let gate = PlaceholderFactory.wallIdentity(
            for: Tile(kind: .gate(minigame: .spelling)),
            at: a,
            in: world
        )
        #expect(solid == nil)
        #expect(gate == "gate|spelling|\(WallFaceSet.all.rawValue)")

        let letterMatch = PlaceholderFactory.wallIdentity(
            for: Tile(kind: .gate(minigame: .letterMatch)),
            at: a,
            in: world
        )
        #expect(letterMatch == "gate|letter_match|\(WallFaceSet.all.rawValue)")
        #expect(letterMatch != gate)

        // Face culling applies to gates (east opaque neighbor hides .right).
        world.setTile(Tile(kind: .wall), at: GridCoord(x: 2, y: 1, story: 0))
        let culled = PlaceholderFactory.wallIdentity(
            for: Tile(kind: .gate(minigame: .spelling)),
            at: a,
            in: world
        )
        #expect(culled != gate)
        #expect(culled == "gate|spelling|\(WallFaceSet([.left, .top]).rawValue)")
    }

    @Test func solidWallTileNodeDrawsNothing() {
        let config = IsometricConfig()
        let node = PlaceholderFactory.tileNode(
            for: Tile(kind: .wall),
            at: GridCoord(x: 0, y: 0, story: 0),
            config: config
        )
        #expect(node.children.isEmpty)
    }

    @Test func wallIdentityNilForUnrenderedInteriorWall() {
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        for y in 0..<3 {
            for x in 0..<3 {
                world.setTile(
                    Tile(kind: .wall),
                    at: GridCoord(x: x, y: y, story: 0)
                )
            }
        }
        let center = GridCoord(x: 1, y: 1, story: 0)
        #expect(
            PlaceholderFactory.wallIdentity(
                for: Tile(kind: .wall),
                at: center,
                in: world
            ) == nil
        )
        #expect(PlaceholderFactory.ceilingIdentity(at: center, in: world) == nil)
    }

    @Test func floorBehindFrontWallIsOccludedForPickups() {
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        // Wall south of center (higher isometric depth) covers a sprite on the center tile.
        world.setTile(Tile(kind: .wall), at: GridCoord(x: 1, y: 2, story: 0))
        let center = GridCoord(x: 1, y: 1, story: 0)
        #expect(IsometricTileGeometry.hasFrontWallOccluder(at: center, in: world.tiles[0]))
        #expect(IsometricTileGeometry.isAdjacentToOpaqueOccluder(at: center, in: world.tiles[0]))
        #expect(!IsometricTileGeometry.isPickupVisibleFloor(at: center, in: world))
    }

    @Test func interiorFloorClearOfWallsIsVisibleForPickups() {
        // 5×5 open floor — center is at least one tile from every edge (and has no walls).
        let world = TestWorldFactory.emptyFloor(width: 5, height: 5)
        let center = GridCoord(x: 2, y: 2, story: 0)
        #expect(!IsometricTileGeometry.isAdjacentToOpaqueOccluder(at: center, in: world.tiles[0]))
        #expect(IsometricTileGeometry.isPickupVisibleFloor(at: center, in: world))
    }

    @Test func gateToTheEastOccludesPickupFloor() {
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        world.setTile(Tile(kind: .gate(minigame: .spelling)), at: GridCoord(x: 2, y: 1, story: 0))
        let cell = GridCoord(x: 1, y: 1, story: 0)
        #expect(IsometricTileGeometry.isAdjacentToOpaqueOccluder(at: cell, in: world.tiles[0]))
        #expect(!IsometricTileGeometry.isPickupVisibleFloor(at: cell, in: world))
    }

    @Test func wallBehindPickupAlsoBlocksVisibleFloor() {
        var world = TestWorldFactory.emptyFloor(width: 5, height: 5)
        // North wall is behind the sprite in depth, but still adjacent — not allowed.
        world.setTile(Tile(kind: .wall), at: GridCoord(x: 2, y: 1, story: 0))
        let cell = GridCoord(x: 2, y: 2, story: 0)
        #expect(!IsometricTileGeometry.hasFrontWallOccluder(at: cell, in: world.tiles[0]))
        #expect(IsometricTileGeometry.isAdjacentToOpaqueOccluder(at: cell, in: world.tiles[0]))
        #expect(!IsometricTileGeometry.isPickupVisibleFloor(at: cell, in: world))
    }

    @Test func ceilingNodeIsGrayRaisedDiamond() {
        let config = IsometricConfig(tileWidth: 40, tileHeight: 40, wallHeight: 40)
        let node = PlaceholderFactory.ceilingNode(config: config)
        let floorBounds = IsometricTileGeometry.floorPath(config: config).boundingBox
        let ceilingBounds = node.path!.boundingBox
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #expect(node.fillColor.getRed(&r, green: &g, blue: &b, alpha: &a))

        #expect(node.name == "ceiling")
        #expect(abs(r - 0.55) < 0.001 && abs(g - 0.55) < 0.001 && abs(b - 0.55) < 0.001)
        #expect(abs(ceilingBounds.minY - (floorBounds.minY + config.wallHeight)) < 0.001)
        #expect(abs(ceilingBounds.height - floorBounds.height) < 0.001)
    }

    @Test func ceilingSortMatchesWallAtSameCell() {
        let coord = GridCoord(x: 4, y: 5, story: 0)
        let config = IsometricConfig()
        #expect(
            IsometricMath.wallSortValue(for: coord, config: config)
                == IsometricMath.depthSortValue(for: coord, config: config)
        )
    }

    @Test @MainActor
    func highlightedPickupGetsSparkleBehindIcon() {
        let items = ItemsConfig(items: [
            "emitter": ItemDefinition(highlight: HighlightConfig()),
        ])
        let node = PlaceholderFactory.pickupNode(
            kind: .treasure,
            entityID: UUID(),
            config: IsometricConfig(),
            itemsConfig: items,
            treasureItemID: "emitter"
        )
        let glow = node.childNode(withName: SparkleEmitterFactory.nodeName) as? SKEmitterNode
        #expect(glow != nil)
        #expect(glow!.zPosition < PlaceholderFactory.entityBodyZ)
    }

    @Test @MainActor
    func pickupWithoutHighlightHasNoSparkle() {
        let items = ItemsConfig(items: [
            "emitter": ItemDefinition(),
        ])
        let node = PlaceholderFactory.pickupNode(
            kind: .treasure,
            entityID: UUID(),
            config: IsometricConfig(),
            itemsConfig: items,
            treasureItemID: "emitter"
        )
        #expect(node.childNode(withName: SparkleEmitterFactory.nodeName) == nil)
    }

    @Test @MainActor
    func collectAnimationStopsSparkleAndBouncesIcon() throws {
        let items = ItemsConfig(items: [
            "emitter": ItemDefinition(highlight: HighlightConfig()),
        ])
        let node = PlaceholderFactory.pickupNode(
            kind: .treasure,
            entityID: UUID(),
            config: IsometricConfig(),
            itemsConfig: items,
            treasureItemID: "emitter"
        )
        let glow = try #require(
            node.childNode(withName: SparkleEmitterFactory.nodeName) as? SKEmitterNode
        )
        let icon = try #require(node.children.first { !($0 is SKEmitterNode) })
        #expect(glow.particleBirthRate > 0)
        #expect(icon.action(forKey: "pickupBounce") != nil)

        var completed = false
        PlaceholderFactory.playCollectAnimation(on: node) {
            completed = true
        }
        #expect(glow.particleBirthRate == 0)
        #expect(icon.action(forKey: "pickupBounce") == nil)
        #expect(!completed)
    }

    @Test @MainActor
    func defeatAnimationAddsRedSparklesBehindBody() throws {
        let entity = GameEntity(
            letter: "S",
            position: GridCoord(x: 0, y: 0, story: 0),
            enemyTypeID: "spider"
        )
        let node = PlaceholderFactory.entityNode(
            for: entity,
            config: IsometricConfig(),
            fillColor: .gray
        )
        #expect(node.childNode(withName: SparkleEmitterFactory.nodeName) == nil)

        var completed = false
        PlaceholderFactory.playDefeatAnimation(on: node) {
            completed = true
        }

        let glow = try #require(
            node.childNode(withName: SparkleEmitterFactory.nodeName) as? SKEmitterNode
        )
        #expect(glow.zPosition < PlaceholderFactory.entityBodyZ)
        #expect(glow.particleBirthRate > 0)
        #expect(HighlightConfig.enemyDefeat.color == "#FF3B30")
        #expect(node.action(forKey: "defeatFade") != nil)
        #expect(!completed)
    }

    @Test @MainActor
    func combatImpactBurstEmitsFiniteOrangeParticles() {
        #expect(HighlightConfig.combatImpact.color == "#FF9500")
        let burst = SparkleEmitterFactory.makeBurstNode(
            config: .combatImpact,
            referenceHeight: 72,
            particleCount: 24
        )
        #expect(burst.numParticlesToEmit == 24)
        #expect(burst.particleBirthRate > 0)
        #expect(burst.particleColorBlendFactor == 1)
    }
}
