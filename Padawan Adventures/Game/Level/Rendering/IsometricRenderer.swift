import SpriteKit

final class IsometricRenderer {
    let config: IsometricConfig
    let enemyConfig: EnemyConfig
    let spriteLibrary: SpriteLibrary?
    let playerSpriteConfig: SpriteConfig?
    let itemsConfig: ItemsConfig?
    let treasureItemID: String?
    let floorTileSetLibrary: FloorTileSetLibrary?
    let gateSpriteSetLibrary: GateSpriteSetLibrary?
    let worldRoot = SKNode()
    /// Floor terrain — shared band with walls/entities; local z uses increasing grid Y.
    let floorLayer = SKNode()
    /// Solid walls / ceilings — same occlusion band as entities (accumulated z interleaves).
    let wallLayer = SKNode()
    /// Players, enemies, pickups, effects, and gate sprites — siblings so gate occlusion
    /// applies equally to every entity type (not only the moving player).
    let occlusionLayer = SKNode()
    var entityNodes: [UUID: SKNode] = [:]
    /// Stable floor nodes keyed by grid coord so animations are not restarted each render.
    var floorNodes: [GridCoord: SKNode] = [:]
    var floorIdentities: [GridCoord: String] = [:]
    /// Stable wall / gate block nodes keyed by grid coord.
    var wallNodes: [GridCoord: SKNode] = [:]
    var wallIdentities: [GridCoord: String] = [:]
    /// Stable ceiling diamonds keyed by grid coord.
    var ceilingNodes: [GridCoord: SKNode] = [:]
    var ceilingIdentities: [GridCoord: String] = [:]
    /// Canonical gate strips on the visible story — used for entity/gate occlusion.
    var gateOccluders: [PlaceholderFactory.GateOccluder] = []
    /// Strips whose sprite is mid-dissolve. `openGate` has already turned their cells into
    /// floor, so these are all that keeps the fading art sorted against nearby sprites.
    var dissolvingGateOccluders: [PlaceholderFactory.GateOccluder] = []
    /// Rooms the player can reach without crossing a closed gate; everything else is dark.
    var visibility: RoomVisibility.Result = .empty
    /// Cells revealed by the latest render that are waiting to be faded in.
    var revealFadeCells: Set<GridCoord> = []
    /// Entities inside `revealFadeCells`, held so their nodes fade in with the room.
    var revealFadeEntityIDs: Set<UUID> = []
    /// Set by `armRevealFade()` so only a gate opening fades its new room in.
    var fadesNextReveal = false
    /// Story the current `visibility` was computed for (`nil` before the first render).
    var visibilityStory: Int?
    var viewCenter: CGPoint = .zero
    var viewportFocus: CGPoint = .zero
    var viewSize: CGSize = .zero
    /// Only this story's tiles/entities are drawn.
    private(set) var visibleStory: Int = 0
    /// Uniform scale applied to `worldRoot` (fit-to-view).
    private(set) var worldScale: CGFloat = 1

    init(
        config: IsometricConfig = IsometricConfig(),
        enemyConfig: EnemyConfig = .fallback,
        spriteLibrary: SpriteLibrary? = nil,
        playerSpriteConfig: SpriteConfig? = nil,
        itemsConfig: ItemsConfig? = nil,
        treasureItemID: String? = nil,
        floorTileSetLibrary: FloorTileSetLibrary? = nil,
        gateSpriteSetLibrary: GateSpriteSetLibrary? = nil
    ) {
        self.config = config
        self.enemyConfig = enemyConfig
        self.spriteLibrary = spriteLibrary
        self.playerSpriteConfig = playerSpriteConfig
        self.itemsConfig = itemsConfig
        self.treasureItemID = treasureItemID
        self.gateSpriteSetLibrary = gateSpriteSetLibrary
        self.floorTileSetLibrary = floorTileSetLibrary
    }

    func attach(to scene: SKScene) {
        worldRoot.removeFromParent()
        worldRoot.removeAllChildren()
        floorLayer.removeAllChildren()
        wallLayer.removeAllChildren()
        occlusionLayer.removeAllChildren()
        entityNodes.removeAll()
        floorNodes.removeAll()
        floorIdentities.removeAll()
        wallNodes.removeAll()
        wallIdentities.removeAll()
        ceilingNodes.removeAll()
        ceilingIdentities.removeAll()
        gateOccluders = []
        dissolvingGateOccluders = []
        visibility = .empty
        revealFadeCells.removeAll()
        revealFadeEntityIDs.removeAll()
        fadesNextReveal = false
        visibilityStory = nil
        visibleStory = 0
        worldScale = 1

        viewSize = scene.size
        viewCenter = CGPoint(
            x: scene.size.width * (0.5 - scene.anchorPoint.x),
            y: scene.size.height * (0.5 - scene.anchorPoint.y)
        )

        // Floors sit in a lower band so floor/decor art never covers sprites.
        // Walls and entities share the occlusion band and interleave by grid Y.
        floorLayer.zPosition = IsometricMath.floorBandBase
        wallLayer.zPosition = IsometricMath.occlusionBandBase
        occlusionLayer.zPosition = IsometricMath.occlusionBandBase

        worldRoot.addChild(floorLayer)
        worldRoot.addChild(wallLayer)
        worldRoot.addChild(occlusionLayer)
        scene.addChild(worldRoot)
    }

    func render(world: GameWorld, focus: CGPoint) {
        visibleStory = world.playerPosition?.story ?? world.spawn.story

        let story = visibleStory
        guard story >= 0, story < world.storyCount else {
            visibility = .empty
            visibilityStory = nil
            revealFadeCells.removeAll()
            revealFadeEntityIDs.removeAll()
            fadesNextReveal = false
            clearFloorNodes()
            clearWallNodes()
            clearCeilingNodes()
            syncEntities(world.entities)
            updateViewportFocus(focus)
            return
        }

        updateVisibility(world: world, story: story)

        syncFloorNodes(world: world, story: story)
        syncWallNodes(world: world, story: story)
        syncCeilingNodes(world: world, story: story)

        syncEntities(world.entities)
        updateViewportFocus(focus)
    }

    /// Makes the next render's newly reachable rooms start hidden, so a gate opening can
    /// fade them in. Reveals from any other render (level start, restore) appear at once.
    func armRevealFade() {
        fadesNextReveal = true
    }
    /// Locks uniform world scale (1 = native `IsometricConfig` tile size).
    func lockWorldScale(_ scale: CGFloat) {
        worldScale = scale
        updateViewportFocus(viewportFocus)
    }

    /// Scales and centers the viewport so the full grid on `story` fits in the scene.
    @discardableResult
    func fitMapInView(world: GameWorld, story: Int) -> CGPoint {
        let bounds = IsometricMath.mapScreenBounds(
            width: world.width,
            height: world.height,
            story: story,
            config: config
        )
        worldScale = IsometricMath.fitScale(mapBounds: bounds, viewSize: viewSize)
        let focus = IsometricMath.mapCenter(for: bounds)
        updateViewportFocus(focus)
        return focus
    }

    /// Rebuilds tiles if the player moved to a different story.
    @discardableResult
    func updateVisibleStory(for world: GameWorld, focus: CGPoint) -> Bool {
        let story = world.playerPosition?.story ?? world.spawn.story
        guard story != visibleStory else { return false }
        render(world: world, focus: focus)
        return true
    }
    var sceneViewCenter: CGPoint {
        viewCenter
    }

    var currentFocus: CGPoint {
        viewportFocus
    }
}
