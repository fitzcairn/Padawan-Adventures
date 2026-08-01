import SpriteKit
import UIKit

extension PitScene {
    // MARK: - Layout

    /// Matches the previous circle font size (`radius * 1.35` with radius = 5.5% of min side).
    var letterFontSize: CGFloat {
        min(size.width, size.height) * 0.055 * 1.35
    }

    var letterPadding: CGFloat {
        letterFontSize * Self.letterPaddingRatio
    }

    var platformSide: CGFloat {
        (letterFontSize + letterPadding * 2) * Self.platformScale * layoutScale
    }

    /// Half of the platform side (used for placement / jump reach).
    var letterRadius: CGFloat {
        platformSide * 0.5
    }

    /// Jump reach: at least enough to clear one equal-width word band plus vertical slack.
    var maxJumpDistance: CGFloat {
        let bands = max(engine.wordLetterIDs.count, 1)
        let bandWidth = playFieldRect.width / CGFloat(bands)
        let bandReach = hypot(bandWidth * 1.2, playFieldRect.height * 0.55)
        return max(letterRadius * 5.5, bandReach)
    }

    /// Gap between platform AABBs (axis-aligned), in points.
    var platformGap: CGFloat {
        max(letterRadius * 0.12, 4)
    }

    func computeLayoutFrames() {
        // Pad rect matches the world-scale AABB of a 2×2 isometric floor block.
        let padSize = PitArenaLayout.floorPadBounds(config: isoConfig).size
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
    func buildPuzzle() {
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
        if !letterNodes.isEmpty {
            return
        }
        if tryBuildPuzzleLayout() {
            return
        }
        GameLogger.fault(
            .world,
            "pit.buildPuzzle exhausted layout attempts (word=\(engine.targetWord), size=\(Int(size.width))×\(Int(size.height)))"
        )
        installDegeneratePitLayout()
    }

    /// Minimal pads + player when letter placement cannot succeed at this scene size.
    func installDegeneratePitLayout() {
        removeAllChildren()
        letterNodes = [:]
        platformNodes = [:]
        computeLayoutFrames()
        addPad(rect: leftPadRect, name: "leftPad")
        addPad(rect: rightPadRect, name: "rightPad")
        addPlayer(at: CGPoint(x: leftPadRect.midX, y: leftPadRect.midY))
    }

    /// Clears the scene and places pads + letter platforms. Returns false if any
    /// platform could not be placed without overlapping another.
    @discardableResult
    func tryBuildPuzzleLayout() -> Bool {
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
    func rebuildLayoutPreservingLetters() {
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
        if let previousPlayer, let playerNode {
            playerNode.position = previousPlayer
        }
    }

    func addPad(rect: CGRect, name: String) {
        let root = SKNode()
        root.name = name
        root.position = CGPoint(x: rect.midX, y: rect.midY)
        root.zPosition = SceneLayer.pads

        if let cluster = makeFloorPadCluster(
            library: floorTileSetLibrary,
            config: isoConfig,
            using: &placementRNG
        ) {
            root.addChild(cluster)
        } else {
            let fallback = SKShapeNode(rectOf: rect.size, cornerRadius: 6)
            fallback.fillColor = padFill
            fallback.strokeColor = UIColor(white: 0.2, alpha: 1)
            fallback.lineWidth = 2
            fallback.zPosition = SceneLayer.background
            root.addChild(fallback)
        }
        addChild(root)
    }

    /// Minimum center-to-center separation on each axis so AABBs do not overlap.
    func minAxisSeparation(for radius: CGFloat) -> CGFloat {
        radius * 2 + platformGap
    }

    /// Samples a word-letter center, preferring its horizontal band, never overlapping.
    func placeWordLetter(
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

    func placeDecoy(radius: CGFloat, avoiding occupied: [CGPoint]) -> CGPoint? {
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

    func sampleValidPosition(
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

    func gridSearchPosition(
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

    func isValidLetterPosition(
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
}
