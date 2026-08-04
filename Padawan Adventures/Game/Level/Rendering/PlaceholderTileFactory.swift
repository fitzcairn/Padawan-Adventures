import simd
import SpriteKit
import UIKit

extension PlaceholderFactory {
    static func tileNode(
        for tile: Tile,
        at coord: GridCoord,
        in world: GameWorld? = nil,
        config: IsometricConfig,
        floorTileSetLibrary: FloorTileSetLibrary? = nil,
        gateSpriteSetLibrary: GateSpriteSetLibrary? = nil
    ) -> SKNode {
        let container = SKNode()

        switch tile.kind {
        case .floor(let isPit):
            // Drop pits a few pixels so the void reads below neighbouring floor.
            container.position = floorScreenPosition(for: tile, at: coord, config: config)
            container.zPosition = IsometricMath.floorSortValue(for: coord, config: config)
            if let library = floorTileSetLibrary,
               let tileSet = library.tileSet,
               let tileID = tile.floorTileID,
               let texture = library.texture(tileID),
               let frame = library.frame(tileID) {
                let sprite = floorTileNode(
                    tileID: tileID,
                    texture: texture,
                    frame: frame,
                    diamond: tileSet.meta.diamond,
                    config: config
                )
                sprite.zPosition = 0.02
                container.addChild(sprite)
            } else {
                // Fallback diamond only when baked floor art is missing.
                let underlay = horizontalFloorNode(
                    config: config,
                    fillColor: isPit ? pitColor : floorColor
                )
                underlay.strokeColor = .clear
                container.addChild(underlay)
            }

        case .wall:
            break

        case .gate(let minigame):
            let sortCoord = wallSortCoord(for: tile, at: coord, in: world) ?? coord
            container.position = wallScreenPosition(
                for: tile,
                at: coord,
                in: world,
                config: config,
                gateSpriteSetLibrary: gateSpriteSetLibrary
            ) ?? IsometricMath.gridToScreen(coord, config: config)
            container.zPosition = IsometricMath.wallSortValue(for: sortCoord, config: config)

            let strip = world.flatMap { gateStrip(at: coord, minigame: minigame, in: $0) }
            let library = gateSpriteSetLibrary
            if library?.isLoaded == true, let strip, !strip.isCanonical {
                // Partner cell of a sprite strip draws nothing (sprite spans both tiles).
                break
            }
            if let library,
               library.isLoaded,
               let strip,
               strip.isCanonical,
               let texture = library.texture(for: strip.axis),
               let frame = library.frame(for: strip.axis),
               let gateSet = library.gateSet {
                container.addChild(
                    gateSpriteNode(
                        texture: texture,
                        frame: frame,
                        footprintScreenWidths: gateSet.footprintScreenWidths,
                        config: config
                    )
                )
            } else {
                // Colored wall blocks when baked gate art is unavailable or gate is solo.
                let faces = world.map { IsometricTileGeometry.visibleFaces(at: coord, in: $0) } ?? .all
                container.addChild(
                    perspectiveWallNode(color: gateColor(for: minigame), faces: faces, config: config)
                )
            }
        }

        return container
    }

    /// Contiguous 2-tile gate strip sharing `minigame`, if present.
    static func gateStrip(
        at coord: GridCoord,
        minigame: GateMinigameKind,
        in world: GameWorld
    ) -> (partner: GridCoord, axis: GateSpriteSet.Axis, isCanonical: Bool)? {
        func isMatchingGate(_ other: GridCoord) -> Bool {
            guard case .gate(let kind)? = world.tile(at: other)?.kind else { return false }
            return kind == minigame
        }

        let east = coord.neighbor(dx: 1, dy: 0)
        if isMatchingGate(east) {
            return (east, .alongX, true)
        }
        let west = coord.neighbor(dx: -1, dy: 0)
        if isMatchingGate(west) {
            return (west, .alongX, false)
        }
        let south = coord.neighbor(dx: 0, dy: 1)
        if isMatchingGate(south) {
            return (south, .alongY, true)
        }
        let north = coord.neighbor(dx: 0, dy: -1)
        if isMatchingGate(north) {
            return (north, .alongY, false)
        }
        return nil
    }

    /// Front cell of a gate strip (higher isometric depth) for z-sorting.
    static func wallSortCoord(
        for tile: Tile,
        at coord: GridCoord,
        in world: GameWorld?
    ) -> GridCoord? {
        guard case .gate(let minigame) = tile.kind, let world else { return coord }
        guard let strip = gateStrip(at: coord, minigame: minigame, in: world) else {
            return coord
        }
        let a = coord
        let b = strip.partner
        return (a.x + a.y) >= (b.x + b.y) ? a : b
    }

    /// World position for a wall/gate node.
    ///
    /// Gate sprites anchor at the south tip of their iso base. Place that tip on the
    /// south tip of the 2-tile strip's floor footprint so the cobblestone base sits in
    /// the wall seam between the two rooms it joins.
    static func wallScreenPosition(
        for tile: Tile,
        at coord: GridCoord,
        in world: GameWorld?,
        config: IsometricConfig,
        gateSpriteSetLibrary: GateSpriteSetLibrary? = nil
    ) -> CGPoint? {
        guard case .gate(let minigame) = tile.kind,
              let world,
              gateSpriteSetLibrary?.isLoaded == true,
              let strip = gateStrip(at: coord, minigame: minigame, in: world),
              strip.isCanonical else {
            return IsometricMath.gridToScreen(coord, config: config)
        }
        return gateStripSouthTip(coord: coord, partner: strip.partner, config: config)
    }

    /// Fraction of one tile step to push gate sprites further southwest (+Y / down-left).
    static let gateSpriteSouthwestNudge: CGFloat = 0.02

    /// South tip of the combined floor diamonds for a 2-tile gate strip.
    ///
    /// The two diamonds merge into a parallelogram whose lowest point is the south corner
    /// of the front cell, a quarter tile southeast of where the strip's two north corners
    /// average out. Anchoring at that average instead leaves the gate hanging off the
    /// floor towards the back of the room.
    static func gateStripSouthTip(
        coord: GridCoord,
        partner: GridCoord,
        config: IsometricConfig
    ) -> CGPoint {
        let front = coord.x + coord.y >= partner.x + partner.y ? coord : partner
        // `gridToScreen` gives a tile's north corner; its south corner is a tile below.
        let north = IsometricMath.gridToScreen(front, config: config)
        // One tile southwest (+Y) maps to (-tileW/2, -tileH/2) in screen space.
        let nudge = gateSpriteSouthwestNudge
        return CGPoint(
            x: north.x - config.tileWidth * 0.5 * nudge,
            y: north.y - config.tileHeight - config.tileHeight * 0.5 * nudge
        )
    }

    /// Slight overscale so the cobblestone base covers hairline gaps against room floors.
    static let gateSpriteScaleBoost: CGFloat = 1.05

    /// Gate wall sprite sized to a 2-tile iso footprint; anchor at bottom-center.
    static func gateSpriteNode(
        texture: SKTexture,
        frame: GateSpriteSet.Frame,
        footprintScreenWidths: CGFloat,
        config: IsometricConfig
    ) -> SKNode {
        let container = SKNode()
        container.name = "gate-sprite"

        let baseW = max(frame.baseW ?? CGFloat(frame.w), 1)
        let targetWidth = config.tileWidth * footprintScreenWidths * gateSpriteScaleBoost
        let scale = targetWidth / baseW
        let sprite = SKSpriteNode(texture: texture)
        let anchor = frame.anchor ?? GateSpriteSet.Anchor(x: CGFloat(frame.w) / 2, y: CGFloat(frame.h))
        sprite.anchorPoint = CGPoint(
            x: anchor.x / max(CGFloat(frame.w), 1),
            y: 1 - anchor.y / max(CGFloat(frame.h), 1)
        )
        sprite.size = CGSize(
            width: CGFloat(frame.w) * scale,
            height: CGFloat(frame.h) * scale
        )
        sprite.position = .zero
        sprite.zPosition = 0
        container.addChild(sprite)
        return container
    }

    /// Raised gray diamond at wall-top height (CEILING overlay).
    static func ceilingNode(config: IsometricConfig) -> SKShapeNode {
        let node = SKShapeNode(path: IsometricTileGeometry.topWallFacePath(config: config))
        node.name = "ceiling"
        node.lineWidth = 1
        node.fillColor = ceilingColor
        node.strokeColor = UIColor(white: 0.2, alpha: 1)
        return node
    }

    /// Flat-top isometric floor diamond (horizontal tile).
    static func horizontalFloorNode(
        isPit: Bool = false,
        config: IsometricConfig,
        fillColor: UIColor? = nil
    ) -> SKShapeNode {
        let node = SKShapeNode(path: IsometricTileGeometry.floorPath(config: config))
        node.lineWidth = 1
        if let fillColor {
            node.fillColor = fillColor
            node.strokeColor = UIColor(white: 0.2, alpha: 1)
        } else if isPit {
            node.fillColor = pitColor
            node.strokeColor = UIColor(white: 0.1, alpha: 1)
        } else {
            node.fillColor = floorColor
            node.strokeColor = UIColor(white: 0.2, alpha: 1)
        }
        return node
    }

    /// Optional ambient tint shader. Off by default — bake-time photometry +
    /// one-way edge fade already solve seams. Enable only after verifying that
    /// `node.alpha` still drives the room-reveal fade with the custom shader.
    static var enableFloorAmbientShader = false

    private static let floorAmbientShader: SKShader = {
        // Subrect textures may present v_tex_coord in parent-atlas space; we ignore
        // that here and only mix RGB with a uniform ambient (no UV sampling math).
        let source = """
        void main() {
            vec4 texel = texture2D(u_texture, v_tex_coord);
            vec3 ambient = u_ambient;
            float strength = u_ambient_strength;
            vec3 rgb = mix(texel.rgb, ambient, strength);
            gl_FragColor = vec4(rgb, texel.a);
        }
        """
        let shader = SKShader(source: source)
        shader.uniforms = [
            SKUniform(name: "u_ambient", vectorFloat3: SIMD3<Float>(0.45, 0.50, 0.40)),
            SKUniform(name: "u_ambient_strength", float: 0.08),
        ]
        return shader
    }()

    /// Floor tile sprite placed so the art's north corner coincides with the container origin.
    static func floorTileNode(
        tileID: String,
        texture: SKTexture,
        frame: FloorTileSet.Frame,
        diamond: FloorTileSet.Diamond,
        config: IsometricConfig
    ) -> SKNode {
        let container = SKNode()
        container.name = "floor-sprite"
        container.userData = NSMutableDictionary(dictionary: ["floorTileID": tileID])

        let sx = config.tileWidth / max(diamond.w, 1)
        let sy = config.tileHeight / max(diamond.h, 1)
        let sprite = SKSpriteNode(texture: texture)
        sprite.anchorPoint = CGPoint(
            x: frame.anchor.x / max(CGFloat(frame.w), 1),
            y: 1 - frame.anchor.y / max(CGFloat(frame.h), 1)
        )
        sprite.size = CGSize(
            width: CGFloat(frame.w) * sx,
            height: CGFloat(frame.h) * sy
        )
        sprite.position = .zero
        sprite.zPosition = 0
        if enableFloorAmbientShader {
            sprite.shader = floorAmbientShader
        }
        container.addChild(sprite)
        return container
    }

    /// Identity key for reusing base floor nodes across renderer rebuilds.
    static func floorIdentity(for tile: Tile) -> String? {
        guard case .floor(let isPit) = tile.kind else { return nil }
        let id = tile.floorTileID ?? ""
        return "\(id)|\(isPit ? 1 : 0)"
    }

    /// Floor art paving a closed gate's cell, borrowed from a room it opens onto.
    ///
    /// A gate strip is a hole in the floor that only the gate sprite covers, so art
    /// shallower than the tile it stands on — 7-mustafar's slab is a quarter tile deep —
    /// leaves the void showing beside it. Opening the gate turns the strip into floor
    /// anyway, so paving it up front only ever removes a gap.
    static func doorwayFloorTileID(at coord: GridCoord, in world: GameWorld?) -> String? {
        guard let world, world.tile(at: coord)?.isGate == true else { return nil }
        for direction in GridCoord.cardinals {
            let neighbour = coord.neighbor(dx: direction.dx, dy: direction.dy)
            guard let tile = world.tile(at: neighbour), case .floor = tile.kind else { continue }
            if let id = tile.floorTileID { return id }
        }
        return nil
    }

    /// Identity key for reusing paved doorway nodes (nil when the strip has no floor to borrow).
    static func doorwayFloorIdentity(at coord: GridCoord, in world: GameWorld?) -> String? {
        doorwayFloorTileID(at: coord, in: world).map { "doorway|\($0)" }
    }

    /// Floor diamond drawn under a closed gate so the strip reads as ground, not void.
    static func doorwayFloorNode(
        at coord: GridCoord,
        in world: GameWorld?,
        config: IsometricConfig,
        floorTileSetLibrary: FloorTileSetLibrary?
    ) -> SKNode {
        let container = SKNode()
        container.position = IsometricMath.gridToScreen(coord, config: config)
        container.zPosition = IsometricMath.floorSortValue(for: coord, config: config)
        guard let library = floorTileSetLibrary,
              let tileSet = library.tileSet,
              let tileID = doorwayFloorTileID(at: coord, in: world),
              let texture = library.texture(tileID),
              let frame = library.frame(tileID) else {
            return container
        }
        let sprite = floorTileNode(
            tileID: tileID,
            texture: texture,
            frame: frame,
            diamond: tileSet.meta.diamond,
            config: config
        )
        sprite.zPosition = 0.02
        container.addChild(sprite)
        return container
    }

    /// Identity key for reusing wall / gate block nodes (nil when nothing should draw).
    static func wallIdentity(
        for tile: Tile,
        at coord: GridCoord,
        in world: GameWorld,
        gateSpriteSetLibrary: GateSpriteSetLibrary? = nil
    ) -> String? {
        switch tile.kind {
        case .wall:
            return nil
        case .gate(let minigame):
            if gateSpriteSetLibrary?.isLoaded == true {
                guard let strip = gateStrip(at: coord, minigame: minigame, in: world) else {
                    // Solo gate — no spanning sprite; fall back to colored faces.
                    let faces = IsometricTileGeometry.visibleFaces(at: coord, in: world)
                    return "gate|\(minigame.rawValue)|\(faces.rawValue)"
                }
                guard strip.isCanonical else { return nil }
                return "gate|sprite|\(minigame.rawValue)|\(strip.axis.rawValue)"
            }
            let faces = IsometricTileGeometry.visibleFaces(at: coord, in: world)
            return "gate|\(minigame.rawValue)|\(faces.rawValue)"
        case .floor:
            return nil
        }
    }

    /// Ceilings are disabled; keep the API so the renderer sync path no-ops cleanly.
    static func ceilingIdentity(at _: GridCoord, in _: GameWorld) -> String? {
        nil
    }

    /// Perspective wall block: left/right slanted faces + optional top, based on tile sides.
    static func perspectiveWallNode(
        color: UIColor? = nil,
        faces: WallFaceSet = .all,
        config: IsometricConfig
    ) -> SKNode {
        let container = SKNode()
        container.name = "wall-block"

        let base = color ?? wallColor
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        let baseLeft = UIColor(hue: hue, saturation: saturation, brightness: min(1, brightness * 1.05), alpha: alpha)
        let baseRight = UIColor(hue: hue, saturation: saturation, brightness: max(0, brightness * 0.75), alpha: alpha)
        let baseTop = UIColor(hue: hue, saturation: saturation, brightness: min(1, brightness * 1.2), alpha: alpha)

        let stroke = UIColor(white: 0.05, alpha: 1)
        let lineWidth: CGFloat = 2.5

        if faces.contains(.left) {
            let left = SKShapeNode(path: IsometricTileGeometry.leftWallFacePath(config: config))
            left.name = "wall-face-left"
            left.lineWidth = lineWidth
            left.strokeColor = stroke
            left.fillColor = baseLeft
            left.zPosition = wallFaceLeftZ
            container.addChild(left)
        }

        if faces.contains(.right) {
            let right = SKShapeNode(path: IsometricTileGeometry.rightWallFacePath(config: config))
            right.name = "wall-face-right"
            right.lineWidth = lineWidth
            right.strokeColor = stroke
            right.fillColor = baseRight
            right.zPosition = wallFaceRightZ
            container.addChild(right)
        }

        if faces.contains(.top) {
            let top = SKShapeNode(path: IsometricTileGeometry.topWallFacePath(config: config))
            top.name = "wall-face-top"
            top.lineWidth = lineWidth
            top.strokeColor = stroke
            top.fillColor = baseTop
            top.zPosition = wallFaceTopZ
            container.addChild(top)
        }

        return container
    }
}
