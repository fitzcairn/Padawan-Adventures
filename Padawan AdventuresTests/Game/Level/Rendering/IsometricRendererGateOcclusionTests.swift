import CoreGraphics
import SpriteKit
import Testing
import UIKit
@testable import Padawan_Adventures

@MainActor
struct IsometricRendererGateOcclusionTests {
    /// Wall column at x = 5 with a 2-cell gate at y = 4...5, rooms east and west.
    private static let back = GridCoord(x: 5, y: 4, story: 0)
    private static let front = GridCoord(x: 5, y: 5, story: 0)

    private func gatedWorld() -> GameWorld {
        var world = TestWorldFactory.emptyFloor(width: 9, height: 9)
        for y in 0..<9 {
            world.setTile(Tile(kind: .wall), at: GridCoord(x: 5, y: y, story: 0))
        }
        for cell in [Self.back, Self.front] {
            world.setTile(Tile(kind: .gate(minigame: .soundOutWord)), at: cell)
        }
        return world
    }

    /// `openGate` turns the strip into floor while the detached sprite spends the whole
    /// dissolve on screen, so the renderer has to remember the strip. Without it the
    /// player standing in the doorway he just opened is painted over by the fading gate.
    @Test func dissolvingGateStillSortsAgainstEntities() {
        var world = gatedWorld()
        let renderer = IsometricRenderer()

        _ = renderer.detachGateNode(at: Self.back, in: world)
        _ = world.openGate(at: Self.back)

        #expect(PlaceholderFactory.gateOccluders(in: world, story: 0).isEmpty)
        #expect(renderer.entityGateOccluders.map(\.sortCoord) == [Self.front])

        let gateZ = IsometricMath.wallSortValue(for: Self.front, config: renderer.config)
        let playerZ = PlaceholderFactory.entitySortValueAccountingForGates(
            x: Double(Self.back.x),
            y: Double(Self.back.y),
            story: Self.back.story,
            gates: renderer.entityGateOccluders,
            config: renderer.config
        )
        #expect(playerZ > gateZ)
    }

    @Test func attachClearsDissolvingStrips() {
        let world = gatedWorld()
        let renderer = IsometricRenderer()
        _ = renderer.detachGateNode(at: Self.back, in: world)
        #expect(!renderer.dissolvingGateOccluders.isEmpty)

        renderer.attach(to: SKScene(size: CGSize(width: 320, height: 480)))
        #expect(renderer.dissolvingGateOccluders.isEmpty)
    }

    /// Player one tile south of a camera-facing (alongX) door: feet sit on the
    /// cobblestone lip. The drawn player sprite must beat the drawn gate sprite.
    @Test func renderedPlayerOnLipDrawsAboveAlongXGate() throws {
        var world = alongXGatedWorld()
        let lip = GridCoord(x: 6, y: 5, story: 0)
        world.setPlayerPosition(lip)

        let renderer = IsometricRenderer(gateSpriteSetLibrary: Self.seededGateLibrary())
        let scene = SKScene(size: CGSize(width: 320, height: 480))
        renderer.attach(to: scene)
        renderer.render(world: world, focus: .zero)

        let player = try #require(world.entities.first { $0.isPlayer })
        let playerNode = try #require(renderer.entityNodes[player.id])
        let gateNode = try #require(renderer.wallNodes[Self.alongXCanonical])

        #expect(playerNode.parent === renderer.occlusionLayer)
        #expect(gateNode.parent === renderer.occlusionLayer)
        #expect(playerNode.zPosition > gateNode.zPosition)
        #expect(
            Self.maxDrawableAccumulatedZ(playerNode) > Self.maxDrawableAccumulatedZ(gateNode),
            "drawn player sprite must beat drawn gate sprite at the cobblestone lip"
        )
    }

    /// Standing on the strip's front cell (same Y as the gate) used to lose in the
    /// depth buffer because the only advantage was +0.5.
    @Test func renderedPlayerOnAlongXFrontCellDrawsAboveGate() throws {
        var world = alongXGatedWorld()
        world.setPlayerPosition(Self.alongXFront)
        let renderer = IsometricRenderer(gateSpriteSetLibrary: Self.seededGateLibrary())
        let scene = SKScene(size: CGSize(width: 320, height: 480))
        renderer.attach(to: scene)
        renderer.render(world: world, focus: .zero)

        let player = try #require(world.entities.first { $0.isPlayer })
        let playerNode = try #require(renderer.entityNodes[player.id])
        let gateNode = try #require(renderer.wallNodes[Self.alongXCanonical])
        #expect(playerNode.zPosition > gateNode.zPosition)
        #expect(Self.maxDrawableAccumulatedZ(playerNode) > Self.maxDrawableAccumulatedZ(gateNode))
    }

    /// Jetpack crest: even a camera-far sort pose must paint the jumper over the gate.
    @Test func renderedPlayerForcedInFrontOfGateDrawsAbove() throws {
        var world = gatedWorld()
        let behind = GridCoord(x: 4, y: 5, story: 0)
        world.setPlayerPosition(behind)

        let renderer = IsometricRenderer(gateSpriteSetLibrary: Self.seededGateLibrary())
        let scene = SKScene(size: CGSize(width: 320, height: 480))
        renderer.attach(to: scene)
        renderer.render(world: world, focus: .zero)

        let player = try #require(world.entities.first { $0.isPlayer })
        let playerNode = try #require(renderer.entityNodes[player.id])
        let gateNode = try #require(renderer.wallNodes[Self.back] ?? renderer.wallNodes[Self.front])

        renderer.updateEntityDisplayPosition(
            player,
            screenPosition: playerNode.position,
            sortX: Double(behind.x),
            sortY: Double(behind.y),
            sortStory: behind.story,
            gateOcclusion: .account
        )
        #expect(playerNode.zPosition < gateNode.zPosition)

        renderer.updateEntityDisplayPosition(
            player,
            screenPosition: playerNode.position,
            sortX: Double(behind.x),
            sortY: Double(behind.y),
            sortStory: behind.story,
            gateOcclusion: .inFront
        )
        #expect(playerNode.zPosition > gateNode.zPosition)
        #expect(Self.maxDrawableAccumulatedZ(playerNode) > Self.maxDrawableAccumulatedZ(gateNode))
    }

    private static let alongXCanonical = GridCoord(x: 5, y: 4, story: 0)
    private static let alongXFront = GridCoord(x: 6, y: 4, story: 0)

    private func alongXGatedWorld() -> GameWorld {
        var world = TestWorldFactory.emptyFloor(width: 9, height: 9)
        for x in 0..<9 {
            world.setTile(Tile(kind: .wall), at: GridCoord(x: x, y: 4, story: 0))
        }
        for cell in [Self.alongXCanonical, Self.alongXFront] {
            world.setTile(Tile(kind: .gate(minigame: .soundOutWord)), at: cell)
        }
        return world
    }

    private static func seededGateLibrary() -> GateSpriteSetLibrary {
        let library = GateSpriteSetLibrary()
        let gateSet = GateSpriteSet(
            meta: GateSpriteSet.Meta(
                version: 1,
                gateSet: "test",
                size: .init(w: 10, h: 10),
                frameCount: 2,
                footprintTiles: 2,
                footprintScreenWidths: 1.5
            ),
            frames: [
                "along_x": .init(x: 0, y: 0, w: 10, h: 10, anchor: .init(x: 7, y: 10), baseW: 10),
                "along_y": .init(x: 0, y: 0, w: 10, h: 10, anchor: .init(x: 3, y: 10), baseW: 10),
            ]
        )
        let image = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        let texture = SKTexture(image: image)
        library.seedForTesting(
            gateSet: gateSet,
            textures: ["along_x": texture, "along_y": texture]
        )
        return library
    }

    private static func maxDrawableAccumulatedZ(_ node: SKNode) -> CGFloat {
        var best = accumulatedZ(node)
        func walk(_ current: SKNode) {
            for child in current.children {
                if child is SKSpriteNode || child is SKShapeNode {
                    best = max(best, accumulatedZ(child))
                }
                walk(child)
            }
        }
        walk(node)
        return best
    }

    private static func accumulatedZ(_ node: SKNode) -> CGFloat {
        var z = node.zPosition
        var parent = node.parent
        while let current = parent {
            z += current.zPosition
            parent = current.parent
        }
        return z
    }
}
