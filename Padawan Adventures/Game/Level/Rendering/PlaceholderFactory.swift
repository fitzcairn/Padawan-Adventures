import SpriteKit
import UIKit

enum PlaceholderFactory {
    // Explicit sRGB so SKShapeNode fillColor round-trips equal (UIColor.white is gray-space).
    static let floorColor = UIColor(red: 1, green: 1, blue: 1, alpha: 1)
    /// Dark brown pit fill so hazards read clearly against white floors.
    static let pitColor = UIColor(red: 0.28, green: 0.14, blue: 0.06, alpha: 1)
    /// Brighter gray so 1-tile partitions stay readable at fit-scale overview.
    static let wallColor = UIColor(white: 0.72, alpha: 1)
    /// Spelling gate (legacy single gate color).
    static let spellingGateColor = UIColor(red: 0.55, green: 0.9, blue: 0.55, alpha: 1)
    /// Letter-match gate.
    static let letterMatchGateColor = UIColor(red: 0.45, green: 0.75, blue: 1.0, alpha: 1)
    /// Word-plug gate.
    static let wordPlugGateColor = UIColor(red: 1.0, green: 0.78, blue: 0.35, alpha: 1)

    static func gateColor(for minigame: GateMinigameKind) -> UIColor {
        switch minigame {
        case .spelling: spellingGateColor
        case .letterMatch: letterMatchGateColor
        case .wordPlug: wordPlugGateColor
        }
    }
    /// Raised roof fill between wall tops.
    static let ceilingColor = UIColor(red: 0.55, green: 0.55, blue: 0.55, alpha: 1)
    /// Screen-space Y drop for pit tiles so voids read below the surrounding floor.
    static let pitDropPixels: CGFloat = 5

    /// World position for a floor cell, including the pit drop when `isPit`.
    static func floorScreenPosition(
        for tile: Tile,
        at coord: GridCoord,
        config: IsometricConfig
    ) -> CGPoint {
        let screen = IsometricMath.gridToScreen(coord, config: config)
        guard tile.isPit else { return screen }
        return CGPoint(x: screen.x, y: screen.y - pitDropPixels)
    }

    /// Nested z biases must stay well below one depth step and the entity/wall
    /// half-step (`entitySortValue` = depth + 0.5). Floors use a lower parent band;
    /// walls/entities share the occlusion band. With `ignoresSiblingOrder`,
    /// SpriteKit sorts by accumulated z — integer face offsets (+1/+2) used to
    /// let sprites draw over front wall sides while wall tops still won.
    static let wallFaceLeftZ: CGFloat = 0.01
    static let wallFaceRightZ: CGFloat = 0.02
    static let wallFaceTopZ: CGFloat = 0.03
    static let entityBodyZ: CGFloat = 0.01
    static let entityLabelZ: CGFloat = 0.02

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

    /// Descriptor for a 2-tile gate used when interleaving entity/gate draw order.
    struct GateOccluder: Equatable, Sendable {
        var axis: GateSpriteSet.Axis
        var cell: GridCoord
        var partner: GridCoord
        var sortCoord: GridCoord
    }

    /// Canonical gate strips in `world` on `story` (one entry per sprite, not per cell).
    static func gateOccluders(in world: GameWorld, story: Int) -> [GateOccluder] {
        var result: [GateOccluder] = []
        var seen = Set<GridCoord>()
        guard story >= 0, story < world.storyCount else { return result }
        for y in 0..<world.height {
            for x in 0..<world.width {
                let coord = GridCoord(x: x, y: y, story: story)
                guard case .gate(let minigame) = world.tile(at: coord)?.kind else { continue }
                guard let strip = gateStrip(at: coord, minigame: minigame, in: world) else { continue }
                guard strip.isCanonical else { continue }
                guard seen.insert(coord).inserted else { continue }
                seen.insert(strip.partner)
                let sortCoord = (coord.x + coord.y) >= (strip.partner.x + strip.partner.y)
                    ? coord : strip.partner
                result.append(
                    GateOccluder(
                        axis: strip.axis,
                        cell: coord,
                        partner: strip.partner,
                        sortCoord: sortCoord
                    )
                )
            }
        }
        return result
    }

    /// Tiles of slack beyond the 2-cell strip where gate art can still overlap a sprite.
    static let gateSpanPadding: Double = 1

    /// True when the entity is close enough along the strip axis for the gate art to
    /// overlap it on screen.
    ///
    /// The near/far side tests below are half-planes, so without this bound a gate would
    /// reorder every sprite sharing its row or column — including sprites far away that
    /// the art cannot touch. Outside the span, plain depth sorting is correct.
    static func entityOverlapsGateSpan(
        entityX: Double,
        entityY: Double,
        gate: GateOccluder
    ) -> Bool {
        switch gate.axis {
        case .alongX:
            let low = Double(min(gate.cell.x, gate.partner.x)) - gateSpanPadding
            let high = Double(max(gate.cell.x, gate.partner.x)) + gateSpanPadding
            return entityX >= low && entityX <= high
        case .alongY:
            let low = Double(min(gate.cell.y, gate.partner.y)) - gateSpanPadding
            let high = Double(max(gate.cell.y, gate.partner.y)) + gateSpanPadding
            return entityY >= low && entityY <= high
        }
    }

    /// True when the entity is on the camera-near side of the gate (should draw above it).
    ///
    /// Gates are thin walls: `alongX` separates rooms in Y (near = higher Y), `alongY`
    /// separates rooms in X (near = higher X). Standing on the gate line is neither.
    static func entityIsInFrontOfGate(
        entityX: Double,
        entityY: Double,
        axis: GateSpriteSet.Axis,
        cell: GridCoord
    ) -> Bool {
        switch axis {
        case .alongX:
            return entityY > Double(cell.y)
        case .alongY:
            return entityX > Double(cell.x)
        }
    }

    /// True when the entity is on the camera-far side of the gate (gate should draw above).
    static func entityIsBehindGate(
        entityX: Double,
        entityY: Double,
        axis: GateSpriteSet.Axis,
        cell: GridCoord
    ) -> Bool {
        switch axis {
        case .alongX:
            return entityY < Double(cell.y)
        case .alongY:
            return entityX < Double(cell.x)
        }
    }

    /// Entity sort z adjusted so near-side poses beat the gate and far-side poses lose to it.
    ///
    /// Used for players, enemies, and pickup items alike — any sprite that shares the
    /// occlusion layer with gate art.
    static func entitySortValueAccountingForGates(
        x: Double,
        y: Double,
        story: Int,
        gates: [GateOccluder],
        config: IsometricConfig
    ) -> CGFloat {
        var z = IsometricMath.entitySortValue(x: x, y: y, story: story, config: config)
        guard !gates.isEmpty else { return z }

        var aboveFloor = -CGFloat.greatestFiniteMagnitude
        var belowCap = CGFloat.greatestFiniteMagnitude
        for gate in gates {
            guard entityOverlapsGateSpan(entityX: x, entityY: y, gate: gate) else { continue }
            let gateZ = IsometricMath.wallSortValue(for: gate.sortCoord, config: config)
            if entityIsInFrontOfGate(entityX: x, entityY: y, axis: gate.axis, cell: gate.cell) {
                aboveFloor = max(aboveFloor, gateZ + 0.5)
            } else if entityIsBehindGate(entityX: x, entityY: y, axis: gate.axis, cell: gate.cell) {
                belowCap = min(belowCap, gateZ - 0.5)
            }
        }
        if aboveFloor > -CGFloat.greatestFiniteMagnitude {
            z = max(z, aboveFloor)
        }
        if belowCap < CGFloat.greatestFiniteMagnitude {
            // Prefer staying visible when near one gate and far from another.
            if aboveFloor > belowCap {
                z = aboveFloor
            } else {
                z = min(z, belowCap)
            }
        }
        return z
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
    static func gateStripSouthTip(
        coord: GridCoord,
        partner: GridCoord,
        config: IsometricConfig
    ) -> CGPoint {
        let p0 = IsometricMath.gridToScreen(coord, config: config)
        let p1 = IsometricMath.gridToScreen(partner, config: config)
        // One tile southwest (+Y) maps to (-tileW/2, -tileH/2) in screen space.
        let nudge = gateSpriteSouthwestNudge
        return CGPoint(
            x: (p0.x + p1.x) / 2 - config.tileWidth * 0.5 * nudge,
            y: (p0.y + p1.y) / 2 - config.tileHeight - config.tileHeight * 0.5 * nudge
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
        container.addChild(sprite)
        return container
    }

    /// Identity key for reusing base floor nodes across renderer rebuilds.
    static func floorIdentity(for tile: Tile) -> String? {
        guard case .floor(let isPit) = tile.kind else { return nil }
        let id = tile.floorTileID ?? ""
        return "\(id)|\(isPit ? 1 : 0)"
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

    static let playerFillColor = UIColor(red: 0.15, green: 0.55, blue: 1.0, alpha: 1)
    static let defaultEntityFillColor = UIColor(white: 0.9, alpha: 1)

    @MainActor
    static func entityNode(
        for entity: GameEntity,
        config: IsometricConfig,
        fillColor: UIColor? = nil,
        spriteLibrary: SpriteLibrary? = nil,
        spriteConfig: SpriteConfig? = nil,
        itemsConfig: ItemsConfig? = nil,
        enemySprite: (id: String, config: SpriteConfig)? = nil,
        treasureItemID: String? = nil
    ) -> SKNode {
        if let kind = entity.pickupKind {
            return pickupNode(
                kind: kind,
                entityID: entity.id,
                config: config,
                spriteLibrary: spriteLibrary,
                itemsConfig: itemsConfig,
                treasureItemID: treasureItemID
            )
        }

        if entity.isPlayer,
           let library = spriteLibrary,
           let spriteConfig,
           library.animation(named: CompassDirection.down.animationName(locomotion: .idle)) != nil {
            return playerSpriteNode(config: config, library: library, spriteConfig: spriteConfig)
        }

        if entity.isEnemy,
           let library = spriteLibrary,
           let enemySprite,
           library.animation(
               id: enemySprite.id,
               named: CompassDirection.down.animationName(locomotion: .idle)
           ) != nil {
            return enemySpriteNode(
                entityID: entity.id,
                config: config,
                library: library,
                spriteConfig: enemySprite.config,
                libraryID: enemySprite.id
            )
        }

        let container = SKNode()
        container.name = entity.isPlayer ? "player" : "entity-\(entity.id.uuidString)"

        // Tall billboard so the sprite reads clearly above the floor diamond.
        let size = CGSize(width: config.tileWidth * 0.55, height: config.tileHeight * 2.2)
        let rect = SKShapeNode(rectOf: size, cornerRadius: 6)
        rect.fillColor = fillColor
            ?? (entity.isPlayer ? playerFillColor : defaultEntityFillColor)
        rect.strokeColor = .white
        rect.lineWidth = 3
        rect.zPosition = entityBodyZ
        // Feet near the tile center; body extends upward toward the camera's "up".
        rect.position = CGPoint(x: 0, y: size.height * 0.35)

        let label = SKLabelNode(text: String(entity.letter))
        label.fontSize = 22
        label.fontName = AppFont.name
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = rect.position
        label.zPosition = entityLabelZ

        container.addChild(rect)
        container.addChild(label)
        return container
    }

    /// Player container hosting an `AnimatedSpriteNode` (name `"player"`).
    @MainActor
    static func playerSpriteNode(
        config: IsometricConfig,
        library: SpriteLibrary,
        spriteConfig: SpriteConfig
    ) -> SKNode {
        let container = SKNode()
        container.name = "player"
        container.userData = NSMutableDictionary(dictionary: ["usesSpriteAnimation": true])

        let height = spriteDisplayHeight(isoConfig: config, spriteConfig: spriteConfig)
        let sprite = AnimatedSpriteNode(size: CGSize(width: height, height: height))
        sprite.targetHeight = height
        sprite.zPosition = entityBodyZ
        // Shift toward bottom of screen by anchor_correction % of scaled height.
        let correction = height * CGFloat(spriteConfig.anchorCorrection) / 100
        sprite.position = CGPoint(x: 0, y: -correction)
        container.addChild(sprite)

        let idleName = CompassDirection.down.animationName(locomotion: .idle)
        sprite.play(name: idleName, library: library)
        return container
    }

    /// Enemy container hosting an `AnimatedSpriteNode`, keyed to `libraryID` in the sprite library.
    @MainActor
    static func enemySpriteNode(
        entityID: UUID,
        config: IsometricConfig,
        library: SpriteLibrary,
        spriteConfig: SpriteConfig,
        libraryID: String
    ) -> SKNode {
        let container = SKNode()
        container.name = "entity-\(entityID.uuidString)"
        container.userData = NSMutableDictionary(dictionary: ["usesSpriteAnimation": true])

        let height = spriteDisplayHeight(isoConfig: config, spriteConfig: spriteConfig)
        let sprite = AnimatedSpriteNode(size: CGSize(width: height, height: height))
        sprite.targetHeight = height
        sprite.zPosition = entityBodyZ
        // Shift toward bottom of screen by anchor_correction % of scaled height.
        let correction = height * CGFloat(spriteConfig.anchorCorrection) / 100
        sprite.position = CGPoint(x: 0, y: -correction)
        container.addChild(sprite)

        sprite.play(
            name: CompassDirection.down.animationName(locomotion: .idle),
            library: library,
            libraryID: libraryID
        )
        return container
    }

    static func usesSpriteAnimation(_ node: SKNode) -> Bool {
        (node.userData?["usesSpriteAnimation"] as? Bool) == true
    }

    /// Display height = `wall_height` × `scale`. Width follows texture aspect at play time.
    static func spriteDisplayHeight(
        isoConfig: IsometricConfig,
        spriteConfig: SpriteConfig
    ) -> CGFloat {
        isoConfig.wallHeight * CGFloat(spriteConfig.scale)
    }

    /// Provisional square size from wall height (width refined when the texture is known).
    static func spriteDisplaySize(
        isoConfig: IsometricConfig,
        spriteConfig: SpriteConfig
    ) -> CGSize {
        let height = spriteDisplayHeight(isoConfig: isoConfig, spriteConfig: spriteConfig)
        return CGSize(width: height, height: height)
    }

    static let pickupIconSize: CGFloat = 30
    static let pickupBounceAmplitude: CGFloat = 5
    static let healthPickupColor = UIColor.systemRed
    static let energyPickupColor = UIColor.systemYellow
    static let treasurePickupColor = UIColor(red: 0.2, green: 0.75, blue: 0.35, alpha: 1)

    @MainActor
    static func pickupNode(
        kind: PickupKind,
        entityID: UUID,
        config: IsometricConfig,
        spriteLibrary: SpriteLibrary? = nil,
        itemsConfig: ItemsConfig? = nil,
        treasureItemID: String? = nil
    ) -> SKNode {
        let container = SKNode()
        container.name = "pickup-\(entityID.uuidString)"

        // Treasure art is per-level; health/energy keep their PickupKind id.
        let itemID = (kind == .treasure ? treasureItemID : nil) ?? kind.rawValue

        let spriteConfig = itemsConfig?.spriteConfig(id: itemID)

        if let library = spriteLibrary,
           let spriteConfig,
           library.animation(id: itemID, named: "idle") != nil {
            // Display height = wall_height × items.yaml `sprite.scale`.
            let height = spriteDisplayHeight(isoConfig: config, spriteConfig: spriteConfig)
            let correction = height * CGFloat(spriteConfig.anchorCorrection) / 100
            if let highlight = itemsConfig?.highlight(id: itemID) {
                let glow = SparkleEmitterFactory.makeNode(
                    config: highlight,
                    referenceHeight: height
                )
                glow.position = CGPoint(
                    x: 0,
                    y: height * CGFloat(highlight.yOffset) - correction
                )
                container.addChild(glow)
            }
            let sprite = AnimatedSpriteNode(size: CGSize(width: height, height: height))
            sprite.zPosition = entityBodyZ
            // Feet (bottom-middle) on the tile center; optional anchor_correction nudge.
            sprite.position = CGPoint(x: 0, y: -correction)
            container.addChild(sprite)
            // Lock height before play so the first texture assign cannot stick at
            // native frame pixels; re-fit after play in case animate resets size.
            sprite.fitHeight(height)
            sprite.play(name: "idle", library: library, libraryID: itemID)
            sprite.fitHeight(height)
            return container
        }

        // SF Symbol fallback still honors items.yaml scale when present.
        let iconSide = pickupIconSize * CGFloat(spriteConfig?.scale ?? 1)
        let iconY = config.tileHeight * 0.35
        if let highlight = itemsConfig?.highlight(id: itemID) {
            let glow = SparkleEmitterFactory.makeNode(
                config: highlight,
                referenceHeight: iconSide
            )
            glow.position = CGPoint(x: 0, y: iconY)
            container.addChild(glow)
        }

        let sprite = SKSpriteNode(texture: pickupTexture(kind: kind, side: iconSide))
        sprite.size = CGSize(width: iconSide, height: iconSide)
        // Lift slightly above the tile center so the icon sits on the floor diamond.
        sprite.position = CGPoint(x: 0, y: iconY)
        sprite.zPosition = entityBodyZ
        container.addChild(sprite)

        startIdleBounce(on: sprite)
        return container
    }

    static func pickupTexture(kind: PickupKind, side: CGFloat = pickupIconSize) -> SKTexture {
        let systemName: String
        let tint: UIColor
        switch kind {
        case .health:
            systemName = "heart.fill"
            tint = healthPickupColor
        case .energy:
            systemName = "bolt.fill"
            tint = energyPickupColor
        case .treasure:
            systemName = "shippingbox.fill"
            tint = treasurePickupColor
        }

        // Bake the tint into a bitmap — SKTexture ignores UIImage dynamic tints and
        // otherwise draws SF Symbols as black template images.
        let pointSize = max(side, 1)
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
        guard let symbol = UIImage(systemName: systemName, withConfiguration: config) else {
            return SKTexture()
        }
        let size = CGSize(width: pointSize, height: pointSize)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            symbol
                .withTintColor(tint, renderingMode: .alwaysOriginal)
                .draw(in: CGRect(origin: .zero, size: size))
        }
        return SKTexture(image: image)
    }

    static func startIdleBounce(on node: SKNode) {
        node.removeAction(forKey: "pickupBounce")
        let up = SKAction.moveBy(x: 0, y: pickupBounceAmplitude, duration: 0.45)
        up.timingMode = .easeInEaseOut
        let down = SKAction.moveBy(x: 0, y: -pickupBounceAmplitude, duration: 0.45)
        down.timingMode = .easeInEaseOut
        node.run(.repeatForever(.sequence([up, down])), withKey: "pickupBounce")
    }

    /// One bounce then fade; calls `completion` when finished.
    static func playCollectAnimation(on node: SKNode, completion: @escaping () -> Void) {
        SparkleEmitterFactory.stop(in: node)
        let icon = node.children.first { !($0 is SKEmitterNode) } ?? node
        icon.removeAction(forKey: "pickupBounce")
        let up = SKAction.moveBy(x: 0, y: pickupBounceAmplitude, duration: 0.2)
        up.timingMode = .easeInEaseOut
        let down = SKAction.moveBy(x: 0, y: -pickupBounceAmplitude, duration: 0.2)
        down.timingMode = .easeInEaseOut
        let fade = SKAction.fadeOut(withDuration: 0.25)
        node.run(.sequence([
            .run { icon.run(.sequence([up, down])) },
            .wait(forDuration: 0.4),
            fade,
            .run(completion),
        ]))
    }

    /// Duration for gate dissolve + connecting-floor fade-in after a successful puzzle.
    /// Nonisolated so it can be used as a default argument (those are always nonisolated).
    nonisolated static let gateOpenDuration: TimeInterval = 2.0

    /// Gate sprite fades out with sparkles while `revealNodes` — the connecting floor tiles
    /// and whatever art the opened gate uncovers — fade in over the same window.
    ///
    /// Particles do not inherit parent alpha, so gate visuals fade separately from the
    /// emitter. Calls `completion` after the dissolve finishes (and lingering particles die).
    @MainActor
    static func playGateOpenAnimation(
        on gateNode: SKNode?,
        revealNodes: [SKNode],
        duration: TimeInterval = gateOpenDuration,
        referenceHeight: CGFloat,
        timingNode: SKNode,
        completion: @escaping () -> Void
    ) {
        let highlight = HighlightConfig.gateOpen
        for revealed in revealNodes {
            revealed.removeAction(forKey: "gateOpenFloorFade")
            revealed.alpha = 0
            let fadeIn = SKAction.fadeIn(withDuration: duration)
            fadeIn.timingMode = .easeInEaseOut
            revealed.run(fadeIn, withKey: "gateOpenFloorFade")
        }

        if let gateNode {
            let visuals = gateNode.children.filter { !($0 is SKEmitterNode) }
            let glow = SparkleEmitterFactory.makeNode(
                config: highlight,
                referenceHeight: referenceHeight
            )
            glow.position = CGPoint(x: 0, y: referenceHeight * CGFloat(highlight.yOffset))
            gateNode.insertChild(glow, at: 0)

            let fadeOut = SKAction.fadeOut(withDuration: duration)
            fadeOut.timingMode = .easeIn
            for child in visuals {
                child.removeAction(forKey: "gateOpenFade")
                child.run(fadeOut, withKey: "gateOpenFade")
            }

            gateNode.removeAction(forKey: "gateOpenDissolve")
            gateNode.run(.sequence([
                .wait(forDuration: duration * 0.75),
                .run { SparkleEmitterFactory.stop(in: gateNode) },
                .wait(forDuration: max(highlight.lifetime, duration * 0.25)),
                .run {
                    gateNode.removeFromParent()
                    completion()
                },
            ]), withKey: "gateOpenDissolve")
            return
        }

        timingNode.removeAction(forKey: "gateOpenDissolve")
        timingNode.run(.sequence([
            .wait(forDuration: duration),
            .run(completion),
        ]), withKey: "gateOpenDissolve")
    }

    /// Red sparkles while the enemy art fades; calls `completion` when finished.
    ///
    /// Particles do not inherit parent alpha, so the sprite/shape children fade
    /// separately and the emitter birth rate is stopped before removal.
    @MainActor
    static func playDefeatAnimation(on node: SKNode, completion: @escaping () -> Void) {
        let highlight = HighlightConfig.enemyDefeat
        let visuals = node.children.filter { !($0 is SKEmitterNode) }
        let animated = visuals.compactMap { $0 as? AnimatedSpriteNode }.first
        let referenceHeight = animated?.targetHeight
            ?? animated?.size.height
            ?? visuals.first?.frame.height
            ?? 40
        let baseY = animated?.position.y ?? visuals.first?.position.y ?? 0

        let glow = SparkleEmitterFactory.makeNode(
            config: highlight,
            referenceHeight: referenceHeight
        )
        glow.position = CGPoint(
            x: 0,
            y: baseY + referenceHeight * CGFloat(highlight.yOffset)
        )
        node.insertChild(glow, at: 0)

        let fadeDuration = max(highlight.lifetime * 0.9, 0.45)
        let fade = SKAction.fadeOut(withDuration: fadeDuration)
        fade.timingMode = .easeIn
        node.run(.sequence([
            .run {
                for child in visuals {
                    child.run(fade)
                }
            },
            .wait(forDuration: fadeDuration * 0.7),
            .run { SparkleEmitterFactory.stop(in: node) },
            .wait(forDuration: highlight.lifetime),
            .run(completion),
        ]), withKey: "defeatFade")
    }

    static func applyAnimationFrame(_ frame: Int, to node: SKNode) {
        let scales: [CGFloat] = [1.0, 1.06, 1.0, 0.94]
        node.setScale(scales[frame % scales.count])
    }

    static func updateEntityNode(
        _ node: SKNode,
        entity: GameEntity,
        config: IsometricConfig,
        gates: [GateOccluder] = []
    ) {
        node.position = IsometricMath.entityScreenPosition(entity.position, config: config)
        node.zPosition = entitySortValueAccountingForGates(
            x: Double(entity.position.x),
            y: Double(entity.position.y),
            story: entity.position.story,
            gates: gates,
            config: config
        )
    }

}
