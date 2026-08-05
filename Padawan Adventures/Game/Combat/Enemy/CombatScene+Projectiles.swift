import SpriteKit

extension CombatScene {
    func spawnWave(targetLetter: String, shots: [CombatWaveShot]) {
        guard let enemyNode, let playerNode else { return }
        let origin = bodyCenter(of: enemyNode, height: enemySpriteHeight)
        let target = bodyCenter(of: playerNode, height: playerSpriteHeight)
        // One speed for the whole wave, derived from the straight-line reference time,
        // so a longer fanned path costs proportionally more time rather than more speed.
        let referenceDistance = max(hypot(target.x - origin.x, target.y - origin.y), 1)
        let baseSpeed = Double(referenceDistance) / max(engine.config.shotTravelSeconds, 0.05)
        let laneCount = max(shots.count, 1)

        for shot in shots {
            let lane = laneOffset(index: shot.laneIndex, count: laneCount)
            // Stagger spawn X immediately so neighbors are not stacked under one swipe.
            let start = CGPoint(x: origin.x + lane * size.width * 0.18, y: origin.y)
            let drop = start.y - target.y
            // Cubic initial tangent points at c1 — keep c1 almost level with start so the
            // first motion is a hard horizontal fan-out before diving toward the player.
            let c1 = CGPoint(x: start.x + lane * size.width * 0.58, y: start.y - drop * 0.04)
            // Converge late; keep a little residual lateral so paths don't re-cross early.
            let c2 = CGPoint(x: target.x + lane * size.width * 0.12, y: start.y - drop * 0.62)
            let length = cubicBezierLength(start: start, c1: c1, c2: c2, end: target)
            let duration = max(Double(length) / (baseSpeed * shot.speedJitter), 0.2)

            let node = makeShotNode(letter: shot.letter, id: shot.id)
            node.position = start
            node.setScale(0.35)
            addChild(node)

            shotVisuals[shot.id] = ShotVisual(
                pathStart: start,
                pathControl1: c1,
                pathControl2: c2,
                pathEnd: target,
                pathStartedAt: sceneElapsed,
                pathDurationSeconds: duration,
                scaleStartedAt: sceneElapsed,
                scaleDurationSeconds: duration,
                letter: shot.letter,
                isTarget: shot.isTarget,
                role: .inbound,
                node: node
            )
        }
    }

    /// Evenly spaced fan slot in -1...1, lightly jittered inside its own bucket so lanes
    /// never cross and neighbors stay far enough apart for a single-sprite swipe.
    func laneOffset(index: Int, count: Int) -> CGFloat {
        guard count > 1 else { return CGFloat.random(in: -0.08...0.08) }
        let bucket = 2.0 / CGFloat(count)
        let center = -1 + bucket * (CGFloat(index) + 0.5)
        let slack = bucket * 0.2
        return center + CGFloat.random(in: -slack...slack)
    }

    func makeShotNode(letter: String, id: UUID) -> SKNode {
        let shot: SKNode
        if let glyph = LetterSpriteFactory.sprite(
            letter: letter,
            side: shotBaseSize,
            library: letterSpriteSetLibrary
        ) {
            shot = glyph
        } else {
            let shape = SKShapeNode(rectOf: CGSize(width: shotBaseSize, height: shotBaseSize), cornerRadius: 4)
            shape.fillColor = enemyType.fillColor.withAlphaComponent(0.9)
            shape.strokeColor = .white
            shape.lineWidth = 1.5
            let label = SKLabelNode(text: letter)
            label.fontName = AppFont.name
            label.fontSize = shotBaseSize * 0.62
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            label.fontColor = .white
            label.zPosition = 1
            shape.addChild(label)
            shot = shape
        }
        shot.zPosition = Layer.shots
        shot.name = "shot-\(id.uuidString)"
        return shot
    }

    func pathProgress(for visual: ShotVisual) -> CGFloat {
        CGFloat(
            min(1, max(0, (sceneElapsed - visual.pathStartedAt) / max(visual.pathDurationSeconds, 0.05)))
        )
    }

    func syncShotMotion() {
        // Keys snapshot + per-iteration re-read: resolving a wave inside this loop
        // retargets the other sprites, and a stale `visual` would strand the wave.
        for id in Array(shotVisuals.keys) {
            guard let visual = shotVisuals[id] else { continue }
            let t = pathProgress(for: visual)
            visual.node.position = cubicBezier(
                t: t,
                start: visual.pathStart,
                c1: visual.pathControl1,
                c2: visual.pathControl2,
                end: visual.pathEnd
            )
            if visual.role == .inbound {
                let scaleT = CGFloat(
                    min(1, max(0, (sceneElapsed - visual.scaleStartedAt) / max(visual.scaleDurationSeconds, 0.05)))
                )
                visual.node.setScale(0.35 + 0.80 * scaleT)
            }
            if t >= 1 {
                finishShotPath(shotID: id)
            }
        }
    }

    func finishShotPath(shotID: UUID) {
        guard let visual = shotVisuals[shotID] else { return }
        switch visual.role {
        case .inbound:
            resolveImpact(shotID: shotID)
        case .sweepingOff:
            removeShotNode(id: shotID)
            noteResolutionStepFinished()
        case .charging:
            landSprite(shotID: shotID)
            noteResolutionStepFinished()
        }
    }

    /// Proximity test, so a hit registers slightly before the path formally ends.
    func checkImpacts() {
        guard let playerNode else { return }
        let aim = bodyCenter(of: playerNode, height: playerSpriteHeight)
        let playerHitRadius = playerSpriteHeight * 0.45
        for (id, visual) in shotVisuals where visual.role == .inbound {
            let hitRadius = max(shotBaseSize * abs(visual.node.xScale) * 0.5, 12)
            let distance = hypot(
                visual.node.position.x - aim.x,
                visual.node.position.y - aim.y
            )
            if distance <= hitRadius + playerHitRadius {
                resolveImpact(shotID: id)
                // The first arrival fails the wave; the rest are handled by the charge.
                return
            }
        }
    }

    func resolveImpact(shotID: UUID) {
        guard engine.registerWaveImpact(shotID: shotID) else {
            // Wave already resolved — this sprite is stale, drop it silently.
            removeShotNode(id: shotID)
            return
        }
        resolveWaveFailed(reason: .impact(shotID))
    }

    func removeShotNode(id: UUID) {
        shotVisuals[id]?.node.removeFromParent()
        shotVisuals[id] = nil
    }
}
