import SpriteKit
import UIKit

protocol PitSceneDelegate: AnyObject {
    func pitSceneDidUpdateTimer(seconds: Int, urgent: Bool)
    func pitSceneDidSelectWord(_ word: String)
    func pitSceneDidUpdateSolvedCount(_ count: Int)
    func pitSceneDidWin(word: String, starsAwarded: Int)
    func pitSceneDidLose()
}

/// SpriteKit pit puzzle: side pads, hoppable letter platforms, timer-driven engine.
final class PitScene: SKScene {
    weak var pitDelegate: PitSceneDelegate?

    private let puzzleConfig: PitPuzzleConfig
    private let playerFx: SoundEffectTable
    private let pitSpriteSetLibrary: PitSpriteSetLibrary
    private let floorTileSetLibrary: FloorTileSetLibrary
    /// Same isometric footprint as the world engine (`app.yaml` display tiles).
    private let isoConfig: IsometricConfig
    private let spriteLibrary: SpriteLibrary
    private let playerSpriteConfig: SpriteConfig?

    private var engine: PitMinigameEngine
    private var letterNodes: [UUID: SKNode] = [:]
    private var platformNodes: [UUID: SKSpriteNode] = [:]
    private var playerNode: SKNode!
    private var playerSprite: AnimatedSpriteNode?
    private var playerFacingLeft = false
    private var leftPadRect: CGRect = .zero
    private var rightPadRect: CGRect = .zero
    private var playFieldRect: CGRect = .zero
    private var didEnd = false
    private var didSetup = false
    private var isJumping = false
    private var lastUpdateTime: TimeInterval?
    private var placementRNG = SystemRandomNumberGenerator()

    private let padFill = UIColor(red: 0.45, green: 0.28, blue: 0.12, alpha: 1)
    private let platformCorrectTint = UIColor(red: 0.20, green: 0.65, blue: 0.28, alpha: 1)
    private let platformWrongFlash = UIColor.systemYellow
    private let playerFill = UIColor.systemRed

    private static let jumpDuration: TimeInterval = 1.0
    private static let playerLibraryID = "player"
    /// Above pads (z≈1) and letter platforms (z≈10).
    private static let playerZ: CGFloat = 1_000
    private static let connectedSoundActionKey = "pitConnectedSound"
    private static let winSoundActionKey = "pitWinSound"
    /// Extra margin around the letter relative to font size (each side).
    private static let letterPaddingRatio: CGFloat = 0.45
    /// Platform sprites are drawn this much larger than the letter+padding box.
    private static let platformScale: CGFloat = 1.75
    /// Side pads are a 2×2 block of level floor tiles.
    private static let padCols = 2
    private static let padRows = 2
    /// Keep jump platforms clear of the top-center HUD word (44pt) + margin.
    private static let hudWordClearance: CGFloat = 72
    /// Shrinks platform size across placement retries when the field is overcrowded.
    private var layoutScale: CGFloat = 1.0

    init(
        size: CGSize,
        puzzleConfig: PitPuzzleConfig,
        playerFx: SoundEffectTable,
        pitSpriteSetLibrary: PitSpriteSetLibrary,
        floorTileSetLibrary: FloorTileSetLibrary,
        isoConfig: IsometricConfig,
        spriteLibrary: SpriteLibrary,
        playerSpriteConfig: SpriteConfig?
    ) {
        self.puzzleConfig = puzzleConfig
        self.playerFx = playerFx
        self.pitSpriteSetLibrary = pitSpriteSetLibrary
        self.floorTileSetLibrary = floorTileSetLibrary
        self.isoConfig = isoConfig
        self.spriteLibrary = spriteLibrary
        self.playerSpriteConfig = playerSpriteConfig
        self.engine = PitMinigameEngine(config: .init(from: puzzleConfig))
        super.init(size: size)
        scaleMode = .aspectFit
        backgroundColor = .black
        isUserInteractionEnabled = true
        anchorPoint = .zero
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        guard !didSetup else { return }
        didSetup = true
        engine.begin()
        pitDelegate?.pitSceneDidSelectWord(engine.targetWord)
        pitDelegate?.pitSceneDidUpdateSolvedCount(0)
        buildPuzzle()
        playWordSound()
        publishTimer()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard didSetup, !didEnd else { return }
        guard size.width > 1, size.height > 1 else { return }
        guard oldSize != size else { return }
        rebuildLayoutPreservingLetters()
    }

    override func update(_ currentTime: TimeInterval) {
        guard !didEnd else { return }

        let dt = lastUpdateTime.map { min(max(currentTime - $0, 0), 0.05) } ?? (1.0 / 60.0)
        lastUpdateTime = currentTime

        let events = engine.tick(dt: dt)
        for event in events {
            handle(event)
        }
        publishTimer()
    }

    // MARK: - Layout

    /// Matches the previous circle font size (`radius * 1.35` with radius = 5.5% of min side).
    private var letterFontSize: CGFloat {
        min(size.width, size.height) * 0.055 * 1.35
    }

    private var letterPadding: CGFloat {
        letterFontSize * Self.letterPaddingRatio
    }

    private var platformSide: CGFloat {
        (letterFontSize + letterPadding * 2) * Self.platformScale * layoutScale
    }

    /// Half of the platform side (used for placement / jump reach).
    private var letterRadius: CGFloat {
        platformSide * 0.5
    }

    /// Jump reach: at least enough to clear one equal-width word band plus vertical slack.
    private var maxJumpDistance: CGFloat {
        let bands = max(engine.wordLetterIDs.count, 1)
        let bandWidth = playFieldRect.width / CGFloat(bands)
        let bandReach = hypot(bandWidth * 1.2, playFieldRect.height * 0.55)
        return max(letterRadius * 5.5, bandReach)
    }

    /// Gap between platform AABBs (axis-aligned), in points.
    private var platformGap: CGFloat {
        max(letterRadius * 0.12, 4)
    }

    private func computeLayoutFrames() {
        // Pad rect matches the world-scale AABB of a 2×2 isometric floor block.
        let padSize = Self.floorPadBounds(config: isoConfig).size
        let padY = (size.height - padSize.height) * 0.5
        leftPadRect = CGRect(x: 0, y: padY, width: padSize.width, height: padSize.height)
        rightPadRect = CGRect(
            x: size.width - padSize.width,
            y: padY,
            width: padSize.width,
            height: padSize.height
        )
        let fieldInset = letterRadius + platformGap
        // Top of scene is high Y; reserve space so jump tiles sit below the HUD word.
        let topInset = max(Self.hudWordClearance, fieldInset)
        let bottomInset = fieldInset
        playFieldRect = CGRect(
            x: leftPadRect.maxX + fieldInset,
            y: bottomInset,
            width: max(rightPadRect.minX - leftPadRect.maxX - fieldInset * 2, letterRadius * 2),
            height: max(size.height - bottomInset - topInset, letterRadius * 2)
        )
    }

    /// Axis-aligned bounds of a `padCols`×`padRows` isometric floor diamond block.
    private static func floorPadBounds(config: IsometricConfig) -> CGRect {
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        let corners = IsometricTileGeometry.floorCorners(config: config)
        for row in 0..<padRows {
            for col in 0..<padCols {
                let origin = IsometricMath.gridToScreen(
                    GridCoord(x: col, y: row, story: 0),
                    config: config
                )
                for point in [corners.north, corners.east, corners.south, corners.west] {
                    let world = CGPoint(x: origin.x + point.x, y: origin.y + point.y)
                    minX = min(minX, world.x)
                    maxX = max(maxX, world.x)
                    minY = min(minY, world.y)
                    maxY = max(maxY, world.y)
                }
            }
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func buildPuzzle() {
        layoutScale = 1.0
        for attempt in 0..<14 {
            if attempt > 0 {
                layoutScale *= 0.88
            }
            if tryBuildPuzzleLayout() {
                return
            }
        }
        // Last resort: keep shrinking until placements succeed (always non-overlapping).
        while layoutScale > 0.15, !tryBuildPuzzleLayout() {
            layoutScale *= 0.85
        }
        if letterNodes.isEmpty {
            _ = tryBuildPuzzleLayout()
        }
    }

    /// Clears the scene and places pads + letter platforms. Returns false if any
    /// platform could not be placed without overlapping another.
    @discardableResult
    private func tryBuildPuzzleLayout() -> Bool {
        removeAllChildren()
        letterNodes = [:]
        platformNodes = [:]
        computeLayoutFrames()

        let radius = letterRadius
        let side = platformSide
        guard side > 1, playFieldRect.width >= side, playFieldRect.height >= side else {
            return false
        }

        // Resolve all centers first so a failed attempt never leaves a partial layout.
        var placedCenters: [CGPoint] = []
        var planned: [(token: PitMinigameEngine.LetterToken, position: CGPoint)] = []
        let startAnchor = CGPoint(x: leftPadRect.midX, y: leftPadRect.midY)
        var previous = startAnchor
        let wordCount = engine.wordLetterIDs.count

        for (index, id) in engine.wordLetterIDs.enumerated() {
            guard let token = engine.letter(id: id) else { continue }
            guard let position = placeWordLetter(
                index: index,
                count: wordCount,
                near: previous,
                radius: radius,
                avoiding: placedCenters
            ) else {
                return false
            }
            planned.append((token, position))
            placedCenters.append(position)
            previous = position
        }

        let wordIDs = Set(engine.wordLetterIDs)
        for token in engine.letters where !wordIDs.contains(token.id) {
            guard let position = placeDecoy(radius: radius, avoiding: placedCenters) else {
                return false
            }
            planned.append((token, position))
            placedCenters.append(position)
        }

        addPad(rect: leftPadRect, name: "leftPad")
        addPad(rect: rightPadRect, name: "rightPad")

        for entry in planned {
            let node = makeLetterNode(token: entry.token, side: side)
            node.position = entry.position
            addChild(node)
            letterNodes[entry.token.id] = node
        }

        addPlayer(at: startAnchor)
        return true
    }

    private func addPlayer(at position: CGPoint) {
        playerSprite = nil
        playerFacingLeft = false
        let height = playerDisplayHeight

        if let config = playerSpriteConfig,
           spriteLibrary.animation(id: Self.playerLibraryID, named: "idle_right") != nil
            || spriteLibrary.animation(id: Self.playerLibraryID, named: "idle_down") != nil {
            let sprite = AnimatedSpriteNode(size: CGSize(width: height, height: height))
            sprite.fitHeight(height)
            // Above pad tiles / letters (pad tiles use small local z; world depthSort is huge).
            sprite.zPosition = Self.playerZ
            sprite.name = "player"
            sprite.position = position
            addChild(sprite)
            playerNode = sprite
            playerSprite = sprite
            // Match world feet nudge when configured.
            let correction = height * CGFloat(config.anchorCorrection) / 100
            sprite.position = CGPoint(x: position.x, y: position.y - correction)
            resumePlayerIdle()
            return
        }

        let radius = max(height * 0.28, 12)
        let fallback = SKShapeNode(circleOfRadius: radius)
        fallback.fillColor = playerFill
        fallback.strokeColor = UIColor(white: 0.9, alpha: 1)
        fallback.lineWidth = 2
        fallback.position = position
        fallback.zPosition = Self.playerZ
        fallback.name = "player"
        addChild(fallback)
        playerNode = fallback
    }

    private var playerDisplayHeight: CGFloat {
        if let config = playerSpriteConfig {
            return max(
                PlaceholderFactory.spriteDisplayHeight(isoConfig: isoConfig, spriteConfig: config),
                48
            )
        }
        return max(letterRadius * 2.4, 48)
    }

    private func resumePlayerIdle() {
        guard let playerSprite else { return }
        let preferred = playerFacingLeft ? "idle_left" : "idle_right"
        let name: String
        if spriteLibrary.animation(id: Self.playerLibraryID, named: preferred) != nil {
            name = preferred
        } else {
            name = "idle_down"
        }
        playPlayerLoop(name)
    }

    private func playPlayerLoop(_ name: String) {
        guard let playerSprite else { return }
        playerSprite.play(name: name, library: spriteLibrary, libraryID: Self.playerLibraryID)
        playerSprite.fitHeight(playerDisplayHeight)
    }

    private func playJumpAnimation(toward target: CGPoint) {
        guard let playerSprite else { return }
        playerFacingLeft = target.x < playerNode.position.x - 0.5
        let name = playerFacingLeft ? "jump_left" : "jump_right"
        playerSprite.playOnce(name: name, library: spriteLibrary, libraryID: Self.playerLibraryID)
        playerSprite.fitHeight(playerDisplayHeight)
    }

    private func rebuildLayoutPreservingLetters() {
        let previousPositions = letterNodes.mapValues(\.position)
        let previousPlayer = playerNode?.position
        buildPuzzle()
        let radius = letterRadius
        var placedCenters: [CGPoint] = []
        for id in engine.wordLetterIDs + engine.letters.map(\.id).filter({ !engine.wordLetterIDs.contains($0) }) {
            guard let node = letterNodes[id] else { continue }
            if let previous = previousPositions[id],
               isValidLetterPosition(previous, radius: radius, avoiding: placedCenters) {
                node.position = previous
                placedCenters.append(previous)
            } else {
                // Keep the freshly laid-out non-overlapping position from buildPuzzle.
                placedCenters.append(node.position)
            }
        }
        if let previousPlayer {
            playerNode.position = previousPlayer
        }
    }

    private func addPad(rect: CGRect, name: String) {
        let root = SKNode()
        root.name = name
        root.position = CGPoint(x: rect.midX, y: rect.midY)
        root.zPosition = 1

        if let cluster = makeFloorPadCluster() {
            root.addChild(cluster)
        } else {
            let fallback = SKShapeNode(rectOf: rect.size, cornerRadius: 6)
            fallback.fillColor = padFill
            fallback.strokeColor = UIColor(white: 0.2, alpha: 1)
            fallback.lineWidth = 2
            fallback.zPosition = 0
            root.addChild(fallback)
        }
        addChild(root)
    }

    /// Builds a 2×2 isometric floor block at the world engine's tile scale / perspective.
    private func makeFloorPadCluster() -> SKNode? {
        guard let tileSet = floorTileSetLibrary.tileSet else { return nil }
        let floorIDs = tileSet.floorTileIDs
        guard !floorIDs.isEmpty else { return nil }

        let config = isoConfig
        let cluster = SKNode()
        let bounds = Self.floorPadBounds(config: config)

        for row in 0..<Self.padRows {
            for col in 0..<Self.padCols {
                let coord = GridCoord(x: col, y: row, story: 0)
                let origin = IsometricMath.gridToScreen(coord, config: config)
                let tid = floorIDs[Int.random(in: 0..<floorIDs.count, using: &placementRNG)]
                guard let texture = floorTileSetLibrary.texture(tid),
                      let frame = tileSet.frames[tid] else {
                    continue
                }
                let tile = PlaceholderFactory.floorTileNode(
                    tileID: tid,
                    texture: texture,
                    frame: frame,
                    diamond: tileSet.meta.diamond,
                    config: config
                )
                tile.position = origin
                // Local painter order only — world `floorSortValue` is ~10k×row and
                // buries the player when the SKView uses ignoresSiblingOrder / parent z sum.
                tile.zPosition = CGFloat(row) * 10 + CGFloat(col)
                cluster.addChild(tile)
            }
        }

        guard !cluster.children.isEmpty, bounds.width > 0, bounds.height > 0 else { return nil }

        // Center on the pad midpoint at 1:1 world scale (no squash — keeps perspective).
        cluster.position = CGPoint(x: -bounds.midX, y: -bounds.midY)
        return cluster
    }

    private func makeLetterNode(token: PitMinigameEngine.LetterToken, side: CGFloat) -> SKNode {
        let root = SKNode()
        root.name = "letter:\(token.id.uuidString)"
        root.userData = ["id": token.id.uuidString, "letter": token.letter]
        root.zPosition = 10

        var spriteHeight = side
        if let texture = pitSpriteSetLibrary.randomTexture(using: &placementRNG),
           let sprite = PitSpriteFactory.sprite(texture: texture, side: side) {
            sprite.zPosition = 0
            sprite.alpha = 0.90 // spritesheet platform only — letters stay fully opaque
            if engine.isSpent(token.id) {
                applyPlatformTint(sprite, color: platformCorrectTint, blend: 0.45)
            }
            root.addChild(sprite)
            platformNodes[token.id] = sprite
            spriteHeight = sprite.size.height
        } else {
            let fallback = SKShapeNode(circleOfRadius: side * 0.5)
            fallback.fillColor = UIColor(white: 0.22, alpha: 1)
            fallback.strokeColor = UIColor(white: 0.65, alpha: 1)
            fallback.lineWidth = 2
            fallback.zPosition = 0
            fallback.alpha = 0.90
            if engine.isSpent(token.id) {
                fallback.fillColor = platformCorrectTint
            }
            root.addChild(fallback)
        }

        let engraved = makeEngravedLetter(text: token.letter, fontSize: letterFontSize)
        // Bottom padding = 10% of sprite height → shift letter up toward the platform top.
        engraved.position = CGPoint(x: 0, y: spriteHeight * 0.10)
        engraved.zPosition = 1
        engraved.alpha = 1
        engraved.isUserInteractionEnabled = false
        root.addChild(engraved)

        return root
    }

    /// Letter with white outline + inner shadow so it reads as carved into the platform.
    private func makeEngravedLetter(text: String, fontSize: CGFloat) -> SKNode {
        let root = SKNode()
        let offset = max(1.0, fontSize * 0.045)

        // 1px white outline (8-neighbor copies behind the engraved stack).
        for dx in -1...1 {
            for dy in -1...1 {
                guard dx != 0 || dy != 0 else { continue }
                let outline = SKLabelNode(text: text)
                outline.fontName = AppFont.name
                outline.fontSize = fontSize
                outline.fontColor = .white
                outline.verticalAlignmentMode = .center
                outline.horizontalAlignmentMode = .center
                outline.position = CGPoint(x: CGFloat(dx), y: CGFloat(dy))
                outline.zPosition = 0
                root.addChild(outline)
            }
        }

        let highlight = SKLabelNode(text: text)
        highlight.fontName = AppFont.name
        highlight.fontSize = fontSize
        highlight.fontColor = UIColor.white.withAlphaComponent(0.30)
        highlight.verticalAlignmentMode = .center
        highlight.horizontalAlignmentMode = .center
        highlight.position = CGPoint(x: offset, y: -offset)
        highlight.zPosition = 1
        root.addChild(highlight)

        let shadow = SKLabelNode(text: text)
        shadow.fontName = AppFont.name
        shadow.fontSize = fontSize
        shadow.fontColor = UIColor.black.withAlphaComponent(0.55)
        shadow.verticalAlignmentMode = .center
        shadow.horizontalAlignmentMode = .center
        shadow.position = CGPoint(x: -offset, y: offset)
        shadow.zPosition = 2
        root.addChild(shadow)

        let label = SKLabelNode(text: text)
        label.fontName = AppFont.name
        label.fontSize = fontSize
        label.fontColor = UIColor(white: 0.10, alpha: 1)
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.zPosition = 3
        label.alpha = 1
        root.addChild(label)

        return root
    }

    private func applyPlatformTint(_ sprite: SKSpriteNode, color: UIColor, blend: CGFloat) {
        sprite.color = color
        sprite.colorBlendFactor = blend
    }

    private func clearPlatformTint(_ sprite: SKSpriteNode) {
        sprite.color = .white
        sprite.colorBlendFactor = 0
    }

    /// Minimum center-to-center separation on each axis so AABBs do not overlap.
    private func minAxisSeparation(for radius: CGFloat) -> CGFloat {
        radius * 2 + platformGap
    }

    /// Samples a word-letter center, preferring its horizontal band, never overlapping.
    private func placeWordLetter(
        index: Int,
        count: Int,
        near previous: CGPoint,
        radius: CGFloat,
        avoiding occupied: [CGPoint]
    ) -> CGPoint? {
        let bands = max(count, 1)
        let bandWidth = playFieldRect.width / CGFloat(bands)
        let bandMinX = playFieldRect.minX + CGFloat(index) * bandWidth
        let bandMaxX = bandMinX + bandWidth
        let maxDist = maxJumpDistance

        // 1) Prefer the word band, within jump reach.
        if let point = sampleValidPosition(
            xMin: bandMinX,
            xMax: bandMaxX,
            radius: radius,
            avoiding: occupied,
            attempts: 160,
            near: previous,
            maxDistance: maxDist
        ) {
            return point
        }

        // 2) Spill into neighbouring bands / full field, still within jump reach.
        if let point = sampleValidPosition(
            xMin: playFieldRect.minX,
            xMax: playFieldRect.maxX,
            radius: radius,
            avoiding: occupied,
            attempts: 200,
            near: previous,
            maxDistance: maxDist
        ) {
            return point
        }

        // 3) Dense grid within jump reach.
        if let point = gridSearchPosition(
            radius: radius,
            avoiding: occupied,
            near: previous,
            maxDistance: maxDist
        ) {
            return point
        }

        // 4) Any non-overlapping slot (jump may be longer — still better than overlap).
        return gridSearchPosition(radius: radius, avoiding: occupied, near: nil, maxDistance: nil)
    }

    private func placeDecoy(radius: CGFloat, avoiding occupied: [CGPoint]) -> CGPoint? {
        if let point = sampleValidPosition(
            xMin: playFieldRect.minX,
            xMax: playFieldRect.maxX,
            radius: radius,
            avoiding: occupied,
            attempts: 160,
            near: nil,
            maxDistance: nil
        ) {
            return point
        }
        return gridSearchPosition(radius: radius, avoiding: occupied, near: nil, maxDistance: nil)
    }

    private func sampleValidPosition(
        xMin: CGFloat,
        xMax: CGFloat,
        radius: CGFloat,
        avoiding occupied: [CGPoint],
        attempts: Int,
        near: CGPoint?,
        maxDistance: CGFloat?
    ) -> CGPoint? {
        let minY = playFieldRect.minY + radius
        let maxY = playFieldRect.maxY - radius
        guard minY <= maxY else { return nil }

        let insetMinX = max(xMin, playFieldRect.minX) + radius
        let insetMaxX = min(xMax, playFieldRect.maxX) - radius
        guard insetMinX <= insetMaxX else { return nil }

        let xRange = insetMinX...insetMaxX
        let yRange = minY...maxY

        for _ in 0..<attempts {
            let point = CGPoint(
                x: CGFloat.random(in: xRange, using: &placementRNG),
                y: CGFloat.random(in: yRange, using: &placementRNG)
            )
            guard isValidLetterPosition(point, radius: radius, avoiding: occupied) else { continue }
            if let near, let maxDistance {
                guard hypot(point.x - near.x, point.y - near.y) <= maxDistance + 0.5 else { continue }
            }
            return point
        }
        return nil
    }

    private func gridSearchPosition(
        radius: CGFloat,
        avoiding occupied: [CGPoint],
        near: CGPoint?,
        maxDistance: CGFloat?
    ) -> CGPoint? {
        let bounds = playFieldRect.insetBy(dx: radius, dy: radius)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        // Step slightly under the separation so the grid can still pack tightly.
        let step = max(minAxisSeparation(for: radius) * 0.5, radius * 0.35)
        var y = bounds.maxY
        while y >= bounds.minY - 0.5 {
            var x = bounds.minX
            while x <= bounds.maxX + 0.5 {
                let point = CGPoint(x: x, y: y)
                if isValidLetterPosition(point, radius: radius, avoiding: occupied) {
                    if let near, let maxDistance {
                        if hypot(point.x - near.x, point.y - near.y) <= maxDistance + 0.5 {
                            return point
                        }
                    } else {
                        return point
                    }
                }
                x += step
            }
            y -= step
        }
        return nil
    }

    private func isValidLetterPosition(
        _ point: CGPoint,
        radius: CGFloat,
        avoiding occupied: [CGPoint]
    ) -> Bool {
        let letterBounds = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        guard playFieldRect.contains(letterBounds) else { return false }
        guard !letterBounds.intersects(leftPadRect.insetBy(dx: -2, dy: -2)),
              !letterBounds.intersects(rightPadRect.insetBy(dx: -2, dy: -2)) else {
            return false
        }

        // Axis-aligned square separation — Euclidean distance alone allows diagonal overlap.
        let sep = minAxisSeparation(for: radius)
        for other in occupied {
            if abs(other.x - point.x) < sep, abs(other.y - point.y) < sep {
                return false
            }
        }
        return true
    }

    // MARK: - Events / audio

    private func handle(_ event: PitEngineEvent) {
        switch event {
        case .timerTick:
            SoundEffectsController.shared.play(event: "timer_tick", from: playerFx)
        case .won:
            break
        case .lost:
            finishLost()
        }
    }

    private func playWordSound() {
        removeAction(forKey: Self.connectedSoundActionKey)
        let trackID = engine.targetSoundTrackID
        guard !trackID.isEmpty else { return }
        SoundEffectsController.shared.play(trackID: trackID)
    }

    /// Progressive prefix cue only — word sound is reserved for incorrect jumps / open / win.
    private func playConnectedPrefixSound(_ prefix: String, then completion: (() -> Void)? = nil) {
        removeAction(forKey: Self.connectedSoundActionKey)
        guard !prefix.isEmpty else {
            completion?()
            return
        }

        let progressiveID = engine.targetEntry.progressiveTrack(forPrefix: prefix)
        var actions: [SKAction] = []
        if let progressiveID, !progressiveID.isEmpty {
            actions.append(SKAction.run {
                SoundEffectsController.shared.play(trackID: progressiveID)
            })
            actions.append(SKAction.wait(forDuration: SoundEffectsController.shared.cueDuration(of: progressiveID)))
        }
        if let completion {
            actions.append(SKAction.run(completion))
        }
        guard !actions.isEmpty else {
            completion?()
            return
        }
        run(SKAction.sequence(actions), withKey: Self.connectedSoundActionKey)
    }

    private func publishTimer() {
        let seconds = max(0, Int(ceil(engine.remainingTime - 1e-9)))
        pitDelegate?.pitSceneDidUpdateTimer(seconds: seconds, urgent: seconds <= 5)
    }

    private func finishWon() {
        guard !didEnd else { return }
        didEnd = true
        isUserInteractionEnabled = false

        let spellingID = engine.targetSoundTrackID
        var actions: [SKAction] = []
        if !spellingID.isEmpty {
            actions.append(SKAction.run {
                SoundEffectsController.shared.play(trackID: spellingID)
            })
            actions.append(SKAction.wait(forDuration: SoundEffectsController.shared.cueDuration(of: spellingID)))
        }
        actions.append(SKAction.run { [weak self] in
            guard let self else { return }
            SoundEffectsController.shared.play(
                event: "win",
                from: SoundEffectsController.shared.commonFx.merging(self.puzzleConfig.fx)
            )
        })
        let word = engine.targetWord
        let stars = engine.targetWord.count
        actions.append(SKAction.run { [weak self] in
            self?.pitDelegate?.pitSceneDidWin(word: word, starsAwarded: stars)
        })
        run(SKAction.sequence(actions), withKey: Self.winSoundActionKey)
    }

    private func finishLost() {
        guard !didEnd else { return }
        didEnd = true
        isUserInteractionEnabled = false
        SoundEffectsController.shared.play(
            event: "lose",
            from: SoundEffectsController.shared.commonFx.merging(puzzleConfig.fx)
        )
        pitDelegate?.pitSceneDidLose()
    }

    // MARK: - Touch / jump

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !didEnd, !isJumping, let touch = touches.first else { return }
        let location = touch.location(in: self)
        guard let node = letterNode(at: location),
              let idString = node.userData?["id"] as? String,
              let id = UUID(uuidString: idString) else {
            return
        }
        guard !engine.isSpent(id) else { return }

        let distance = hypot(node.position.x - playerNode.position.x, node.position.y - playerNode.position.y)
        guard distance <= maxJumpDistance + 0.5 else { return }

        guard let result = engine.acceptLetter(id: id) else { return }
        let origin = playerNode.position
        isJumping = true

        switch result {
        case let .correct(prefix, won):
            jumpPlayer(to: node.position) { [weak self] in
                guard let self else { return }
                if let platform = self.platformNodes[id] {
                    self.applyPlatformTint(platform, color: self.platformCorrectTint, blend: 0.45)
                }
                self.pitDelegate?.pitSceneDidUpdateSolvedCount(prefix.count)
                self.playConnectedPrefixSound(prefix) {
                    if won {
                        let exit = CGPoint(x: self.rightPadRect.midX, y: self.rightPadRect.midY)
                        self.jumpPlayer(to: exit, landAnimation: "celebrate_down") {
                            self.isJumping = false
                            self.finishWon()
                        }
                    } else {
                        self.isJumping = false
                    }
                }
            }
        case .incorrect:
            jumpPlayer(to: node.position) { [weak self] in
                guard let self else { return }
                self.flashWrong(id: id) {
                    self.jumpPlayer(to: origin) {
                        self.playWordSound()
                        self.isJumping = false
                    }
                }
            }
        }
    }

    private func letterNode(at point: CGPoint) -> SKNode? {
        let hits = nodes(at: point)
        for hit in hits {
            var current: SKNode? = hit
            while let node = current {
                if let name = node.name, name.hasPrefix("letter:") {
                    return node
                }
                current = node.parent
            }
        }
        return nil
    }

    private func jumpPlayer(
        to target: CGPoint,
        landAnimation: String? = nil,
        completion: @escaping () -> Void
    ) {
        let start = playerNode.position
        playJumpAnimation(toward: target)
        let arcHeight = max(letterRadius * 2.2, hypot(target.x - start.x, target.y - start.y) * 0.35)
        let control = CGPoint(
            x: (start.x + target.x) * 0.5,
            y: max(start.y, target.y) + arcHeight
        )
        let duration = Self.jumpDuration
        let action = SKAction.customAction(withDuration: duration) { [weak self] _, elapsedTime in
            guard let self else { return }
            let linearT = min(max(elapsedTime / CGFloat(duration), 0), 1)
            // Smoothstep ease-in / ease-out.
            let t = linearT * linearT * (3 - 2 * linearT)
            let oneMinus = 1 - t
            let x = oneMinus * oneMinus * start.x + 2 * oneMinus * t * control.x + t * t * target.x
            let y = oneMinus * oneMinus * start.y + 2 * oneMinus * t * control.y + t * t * target.y
            self.playerNode.position = CGPoint(x: x, y: y)
        }
        playerNode.run(action) {
            self.playerNode.position = target
            if let landAnimation,
               self.spriteLibrary.animation(id: Self.playerLibraryID, named: landAnimation) != nil {
                self.playPlayerLoop(landAnimation)
            } else {
                self.resumePlayerIdle()
            }
            completion()
        }
    }

    private func flashWrong(id: UUID, completion: @escaping () -> Void) {
        guard let platform = platformNodes[id] else {
            completion()
            return
        }
        let flash = SKAction.doubleFlash(
            apply: { self.applyPlatformTint(platform, color: self.platformWrongFlash, blend: 0.55) },
            clear: { self.clearPlatformTint(platform) }
        )
        platform.run(flash, completion: completion)
    }
}
