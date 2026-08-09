import SpriteKit
import UIKit

extension PitSoundOutWordScene {
    // MARK: - Step flow

    func beginStep() {
        guard !didEnd, engine.currentIndex != nil else { return }
        revealCandidates()
        flashActiveGraphemeAndSayName()
        isUserInteractionEnabled = true
    }

    func flashActiveGraphemeAndSayName() {
        guard let index = engine.currentIndex,
              let grapheme = engine.currentGrapheme else { return }
        flashGrapheme(
            at: index,
            apply: .white,
            clear: activeGraphemeColor,
            count: 2
        )
        if let trackID = engine.nameTrackID(for: grapheme) {
            SoundEffectsController.shared.play(trackID: trackID)
        }
    }

    func revealCandidates() {
        for node in candidateNodes {
            node.removeFromParent()
        }
        candidateNodes = []

        guard let stepIndex = engine.currentIndex else { return }
        let geo = geometry
        let count = engine.currentChoices.count
        let jitters = geo.candidateJitters(step: stepIndex, count: count, using: &placementRNG)
        for (index, choice) in engine.currentChoices.enumerated() {
            let jitter = jitters[index]
            let node = makeCandidateTileNode(
                choice: choice,
                index: index,
                stepIndex: stepIndex,
                jitter: jitter
            )
            let center = geo.candidateCenter(step: stepIndex, candidate: index, count: count)
            node.position = CGPoint(x: center.x + jitter.x, y: center.y + jitter.y)
            node.alpha = 0
            addChild(node)
            candidateNodes.append(node)
            node.run(SKAction.fadeIn(withDuration: 0.2))
        }
    }

    func makeCandidateTileNode(
        choice: GateSoundOutWordEngine.Choice,
        index: Int,
        stepIndex: Int,
        jitter: CGPoint
    ) -> SKNode {
        let side = geometry.tileSide
        let root = SKNode()
        root.name = "candidate:\(index)"
        root.userData = [
            "id": choice.id.uuidString,
            "grapheme": choice.grapheme,
            "index": index,
            "step": stepIndex,
            "count": engine.currentChoices.count,
            "jitterX": jitter.x,
            "jitterY": jitter.y,
        ]
        root.zPosition = Self.candidateTilesZ

        if let tile = makeFloorTileNode(
            library: floorTileSetLibrary,
            config: isoConfig,
            using: &placementRNG
        ) {
            let measured = tile.calculateAccumulatedFrame()
            if measured.width > 1 {
                tile.setScale(side / measured.width)
            }
            let bounds = tile.calculateAccumulatedFrame()
            tile.position = CGPoint(x: -bounds.midX, y: -bounds.midY)
            tile.zPosition = 0
            root.addChild(tile)
        } else {
            let fallback = SKShapeNode(
                rectOf: CGSize(width: side, height: side * 0.6),
                cornerRadius: 4
            )
            fallback.fillColor = UIColor(white: 0.22, alpha: 1)
            fallback.strokeColor = UIColor(white: 0.65, alpha: 1)
            fallback.lineWidth = 2
            fallback.zPosition = 0
            root.addChild(fallback)
        }

        let symbol = MinigamePlaySoundIcon.makeNode(side: side * Self.playSymbolSideRatio)
        symbol.position = CGPoint(
            x: MinigamePlaySoundIcon.opticalXOffset(containerWidth: side),
            y: 0
        )
        symbol.zPosition = 1
        root.addChild(symbol)

        return root
    }

    func playCandidateSound(tile: SKNode) {
        guard !isDraggingPlayer else { return }
        let grapheme = (tile.userData?["grapheme"] as? String) ?? ""
        guard let trackID = engine.soundTrackID(for: grapheme), !trackID.isEmpty else { return }
        SoundEffectsController.shared.play(trackID: trackID)
        MinigamePlaySoundIcon.pulse(in: tile, forTrackID: trackID)
    }

    // MARK: - Touch / drag

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !didEnd, !isJumping, isUserInteractionEnabled, let touch = touches.first else {
            return
        }
        let location = touch.location(in: self)

        if let region = prompt?.region(at: location) {
            switch region {
            case .picture:
                replayWordSound()
            case .word:
                if let grapheme = engine.currentGrapheme,
                   let trackID = engine.nameTrackID(for: grapheme) {
                    SoundEffectsController.shared.play(trackID: trackID)
                    if let promptNode {
                        MinigameCRTPromptPlate.pulseIcons(in: promptNode, forTrackID: trackID)
                    }
                }
            }
            return
        }

        let hits = nodes(at: location)
        for hit in hits {
            var current: SKNode? = hit
            while let node = current {
                if let name = node.name, name.hasPrefix("candidate:") {
                    playCandidateSound(tile: node)
                    return
                }
                if node.name == "player" {
                    beginPlayerDrag(at: location)
                    return
                }
                current = node.parent
            }
        }

        if let playerNode {
            let radius = playerDisplayHeight * 0.5
            if hypot(location.x - playerNode.position.x, location.y - playerNode.position.y)
                <= radius {
                beginPlayerDrag(at: location)
            }
        }
    }

    func beginPlayerDrag(at location: CGPoint) {
        guard let playerNode, !isDraggingPlayer else { return }
        isDraggingPlayer = true
        dragStartPosition = playerNode.position
        dragOffset = CGPoint(
            x: playerNode.position.x - location.x,
            y: playerNode.position.y - location.y
        )
        playJumpLoop(facingLeft: playerFacingLeft)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isDraggingPlayer, let touch = touches.first, let playerNode else { return }
        let location = touch.location(in: self)
        var next = CGPoint(x: location.x + dragOffset.x, y: location.y + dragOffset.y)
        let half = geometry.tileSide * 0.5
        next.x = min(max(next.x, half), size.width - half)
        next.y = min(max(next.y, half), size.height - half)

        let wasFacingLeft = playerFacingLeft
        let facingLeft = next.x < playerNode.position.x - 0.5
            ? true
            : (next.x > playerNode.position.x + 0.5 ? false : playerFacingLeft)
        playerNode.position = next
        if facingLeft != wasFacingLeft {
            playJumpLoop(facingLeft: facingLeft)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        endPlayerDrag()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        endPlayerDrag()
    }

    func endPlayerDrag() {
        guard isDraggingPlayer, let playerNode else { return }
        isDraggingPlayer = false

        let dx = playerNode.position.x - dragStartPosition.x
        let dy = playerNode.position.y - dragStartPosition.y
        if hypot(dx, dy) <= geometry.tileSide * 0.35 {
            let action = SKAction.move(to: dragStartPosition, duration: Self.settleDuration)
            action.timingMode = .easeOut
            playerNode.run(action) { [weak self] in
                self?.resumePlayerIdle()
            }
            return
        }

        guard let stepIndex = engine.currentIndex else {
            resumePlayerIdle()
            return
        }
        let count = engine.currentChoices.count
        guard count > 0 else {
            resumePlayerIdle()
            return
        }
        // Prefer actual (jittered) tile positions over the geometric fan centres.
        let candidateIndex = nearestCandidateNodeIndex(to: playerNode.position)
            ?? geometry.nearestCandidate(to: playerNode.position, step: stepIndex, count: count)
        let target = candidateNodes.indices.contains(candidateIndex)
            ? candidateNodes[candidateIndex].position
            : geometry.candidateCenter(step: stepIndex, candidate: candidateIndex, count: count)

        isUserInteractionEnabled = false
        playDucked(event: "jump", from: pitFx)
        let move = SKAction.move(to: target, duration: Self.settleDuration)
        move.timingMode = .easeOut
        playerNode.run(move) { [weak self] in
            guard let self else { return }
            // Always face right once standing on a tile.
            self.playerFacingLeft = false
            self.resumePlayerIdle()
            self.evaluate(candidateIndex: candidateIndex)
        }
    }

    /// Nearest live candidate by its on-screen (jittered) position.
    func nearestCandidateNodeIndex(to point: CGPoint) -> Int? {
        guard !candidateNodes.isEmpty else { return nil }
        var bestIndex = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (index, node) in candidateNodes.enumerated() {
            let distance = hypot(point.x - node.position.x, point.y - node.position.y)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }
}
