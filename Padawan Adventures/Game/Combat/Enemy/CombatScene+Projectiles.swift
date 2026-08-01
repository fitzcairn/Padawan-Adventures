import SpriteKit

extension CombatScene {
    func spawnShot(id: UUID, travelSeconds: Double, visualLetter: String) {
        guard let enemyNode else { return }
        // Aim from the live cue so a just-changed letter already dodges or homes correctly.
        let canHitPlayer = visualLetter == engine.sequenceRequiredLetter
        let travel = max(travelSeconds, 0.05)
        let start = bodyCenter(of: enemyNode, height: enemySpriteHeight)
        let end = shotEndPoint(from: start, canHitPlayer: canHitPlayer)
        let control = shotControlPoint(from: start, to: end, canHitPlayer: canHitPlayer)

        let shot: SKNode
        if let glyph = LetterSpriteFactory.sprite(
            letter: visualLetter,
            side: shotBaseSize,
            library: letterSpriteSetLibrary
        ) {
            shot = glyph
        } else {
            let shape = SKShapeNode(rectOf: CGSize(width: shotBaseSize, height: shotBaseSize), cornerRadius: 4)
            shape.fillColor = enemyType.fillColor.withAlphaComponent(0.9)
            shape.strokeColor = .white
            shape.lineWidth = 1.5
            let label = SKLabelNode(text: visualLetter)
            label.fontName = AppFont.name
            label.fontSize = shotBaseSize * 0.62
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            label.fontColor = .white
            label.zPosition = 1
            shape.addChild(label)
            shot = shape
        }
        shot.position = start
        shot.setScale(0.35)
        shot.zPosition = 20
        shot.name = "shot-\(id.uuidString)"
        addChild(shot)

        shotVisuals[id] = ShotVisual(
            pathStart: start,
            pathControl: control,
            pathEnd: end,
            pathSpawnElapsed: engine.elapsed,
            pathTravelSeconds: travel,
            scaleSpawnElapsed: engine.elapsed,
            scaleTravelSeconds: travel,
            canHitPlayer: canHitPlayer,
            visualLetter: visualLetter,
            node: shot
        )
    }

    /// Matching shots aim at the player body; mismatches fly clearly off-screen past them.
    func shotEndPoint(from start: CGPoint, canHitPlayer: Bool) -> CGPoint {
        guard let playerNode else { return start }
        let player = bodyCenter(of: playerNode, height: playerSpriteHeight)
        guard !canHitPlayer else { return player }

        // Pick the side already away from the player so the dodge never crosses them.
        let side: CGFloat = start.x >= player.x ? 1 : -1
        let missX = side < 0 ? -size.width * 0.08 : size.width * 1.08
        let missY = max(player.y - size.height * 0.12, -size.height * 0.05)
        return CGPoint(x: missX, y: missY)
    }

    func shotControlPoint(from start: CGPoint, to end: CGPoint, canHitPlayer: Bool) -> CGPoint {
        let mid = CGPoint(x: (start.x + end.x) * 0.5, y: (start.y + end.y) * 0.5)
        if canHitPlayer {
            let lateral = CGFloat.random(in: -size.width * 0.42...size.width * 0.42)
            return CGPoint(x: mid.x + lateral, y: mid.y)
        }
        // Strong outward bend so non-targets obviously swerve around the player.
        guard let playerNode else { return mid }
        let player = bodyCenter(of: playerNode, height: playerSpriteHeight)
        let away: CGFloat = start.x >= player.x ? 1 : -1
        let lateral = away * size.width * CGFloat.random(in: 0.40...0.62)
        return CGPoint(x: mid.x + lateral, y: mid.y + size.height * 0.08)
    }

    /// Retarget in-flight letters when they become / stop being the live phonetic cue.
    func syncShotAiming() {
        let cue = engine.sequenceRequiredLetter
        guard !cue.isEmpty else { return }

        for (id, visual) in shotVisuals {
            let shouldHit = visual.visualLetter == cue
            guard shouldHit != visual.canHitPlayer else { continue }

            let pathT = pathProgress(for: visual)
            let remaining = max(visual.pathTravelSeconds * Double(1 - pathT), 0.35)
            let current = quadraticBezier(
                t: pathT,
                start: visual.pathStart,
                control: visual.pathControl,
                end: visual.pathEnd
            )
            let end = shotEndPoint(from: current, canHitPlayer: shouldHit)
            let control = shotControlPoint(from: current, to: end, canHitPlayer: shouldHit)

            var updated = visual
            updated.pathStart = current
            updated.pathControl = control
            updated.pathEnd = end
            updated.pathSpawnElapsed = engine.elapsed
            updated.pathTravelSeconds = remaining
            updated.canHitPlayer = shouldHit
            updated.node.position = current
            shotVisuals[id] = updated
        }
    }

    func pathProgress(for visual: ShotVisual) -> CGFloat {
        CGFloat(
            min(1, max(0, (engine.elapsed - visual.pathSpawnElapsed) / max(visual.pathTravelSeconds, 0.05)))
        )
    }

    func syncShotMotion() {
        for (id, visual) in shotVisuals {
            let pathT = pathProgress(for: visual)
            let scaleT = CGFloat(
                min(1, max(0, (engine.elapsed - visual.scaleSpawnElapsed) / max(visual.scaleTravelSeconds, 0.05)))
            )
            visual.node.position = quadraticBezier(
                t: pathT,
                start: visual.pathStart,
                control: visual.pathControl,
                end: visual.pathEnd
            )
            visual.node.setScale(0.35 + 0.80 * scaleT)
            if pathT >= 1 {
                finishShotPath(shotID: id)
            }
        }
    }

    func checkImpacts() {
        guard let playerNode else { return }
        let aim = bodyCenter(of: playerNode, height: playerSpriteHeight)
        for (id, visual) in shotVisuals where visual.canHitPlayer {
            let hitRadius = max(shotBaseSize * visual.node.xScale * 0.5, 12)
            let dx = visual.node.position.x - aim.x
            let dy = visual.node.position.y - aim.y
            let playerHitRadius = playerSpriteHeight * 0.45
            if sqrt(dx * dx + dy * dy) <= hitRadius + playerHitRadius {
                resolveImpactIfNeeded(shotID: id)
            }
        }
    }

    func finishShotPath(shotID: UUID) {
        guard let visual = shotVisuals[shotID] else { return }
        if visual.canHitPlayer {
            resolveImpactIfNeeded(shotID: shotID)
        } else {
            // Missed the player — despawn quietly with no damage VFX.
            engine.discardShot(shotID: shotID)
            removeShotNode(id: shotID)
        }
    }

    func resolveImpactIfNeeded(shotID: UUID) {
        guard let visual = shotVisuals[shotID], visual.canHitPlayer else { return }
        guard engine.registerImpact(shotID: shotID) else {
            removeShotNode(id: shotID)
            return
        }
        let position = visual.node.position
        removeShotNode(id: shotID)
        playDamage(at: position)
        for pending in engine.drainPendingEvents() {
            handle(pending)
        }
    }

    func removeShotNode(id: UUID) {
        shotVisuals[id]?.node.removeFromParent()
        shotVisuals[id] = nil
    }
}
