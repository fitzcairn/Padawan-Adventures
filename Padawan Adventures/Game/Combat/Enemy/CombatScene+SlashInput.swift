import QuartzCore
import SpriteKit

extension CombatScene {
    // MARK: - Slash input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !didEnd, !engine.isFrozen else { return }
        guard let touch = touches.first else { return }
        beginSlash(at: touch.location(in: self), time: CACurrentMediaTime())
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !didEnd, !engine.isFrozen, isSlashActive else { return }
        guard let touch = touches.first else { return }
        let now = CACurrentMediaTime()
        let point = touch.location(in: self)
        let reachedLengthCap = appendSlashPoint(point)
        updateSlashLine()
        resolveSlashHits()
        // Cap by path length and/or duration, then fade the saber out.
        if reachedLengthCap || hasSlashTimedOut(at: now) {
            endSlash()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        endSlash()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        endSlash()
    }

    func beginSlash(at point: CGPoint, time: TimeInterval) {
        SoundEffectsController.shared.play(event: "slash", from: playerFx)
        isSlashActive = true
        slashStartedAt = time
        slashPoints = [point]
        slashPathLength = 0
        updateSlashLine()
        if combatSprite != nil, let playerNode {
            playerNode.playOnce(
                name: playerSwingAnimationName,
                library: spriteLibrary,
                libraryID: playerCombatLibraryID
            )
            // Left half of the screen → mirror horizontally so the padawan faces that way.
            // (`playOnce` resets scale from the clip; re-apply facing after.)
            setPlayerFacingLeft(point.x < size.width * 0.5)
        }
    }

    /// Mirrors the player on X. Keeps the UIImage→SKTexture V-inversion on Y.
    func setPlayerFacingLeft(_ faceLeft: Bool) {
        guard let playerNode else { return }
        let magnitude = abs(playerNode.yScale)
        let scale = magnitude > 0 ? magnitude : 1
        playerNode.xScale = faceLeft ? -scale : scale
        playerNode.yScale = playerNode.correctsUIImageVInversion ? -scale : scale
    }

    func endSlash() {
        isSlashActive = false
        slashStartedAt = nil
        clearSlashLine()
        slashPoints = []
        slashPathLength = 0
    }

    func hasSlashTimedOut(at time: TimeInterval) -> Bool {
        guard let started = slashStartedAt else { return false }
        return time - started >= slashMaxSeconds
    }

    var maxSlashPathLength: CGFloat {
        max(size.width * slashMaxScreenWidthFraction, 1)
    }

    /// Appends `point`, clamping to `maxSlashPathLength`. Returns true if the length cap was hit.
    @discardableResult
    func appendSlashPoint(_ point: CGPoint) -> Bool {
        guard let last = slashPoints.last else {
            slashPoints = [point]
            slashPathLength = 0
            return false
        }
        let dx = point.x - last.x
        let dy = point.y - last.y
        let step = hypot(dx, dy)
        guard step > 0.5 else { return false }

        let maxLen = maxSlashPathLength
        let remaining = maxLen - slashPathLength
        if step >= remaining {
            let t = remaining / step
            slashPoints.append(CGPoint(x: last.x + dx * t, y: last.y + dy * t))
            slashPathLength = maxLen
            return true
        }
        slashPoints.append(point)
        slashPathLength += step
        return false
    }
    func resolveSlashHits() {
        guard isSlashActive, slashPoints.count >= 2 else { return }

        // Any overlap between the stroke and the letter sprite bounds counts as a hit.
        let stroke = slashPoints

        for (id, visual) in shotVisuals {
            let bounds = shotSpriteBounds(for: visual.node)
            guard CombatSlashGeometry.slashIntersectsRect(points: stroke, rect: bounds) else {
                continue
            }

            let result = engine.registerSlashHit(shotID: id)
            let pos = visual.node.position
            switch result {
            case .ignored:
                continue
            case .correct:
                removeShotNode(id: id)
                playExplosion(at: pos)
                combatDelegate?.combatSceneDidUpdateStars(engine.combatStars)
                for pending in engine.drainPendingEvents() {
                    handle(pending)
                }
                if engine.hasWon || engine.outcome != nil {
                    finishWin()
                    return
                }
            case .wrong:
                removeShotNode(id: id)
                playIncorrectSlash(at: pos)
                combatDelegate?.combatSceneDidUpdateStars(engine.combatStars)
            }
        }
    }

    /// Axis-aligned bounds of the on-screen letter sprite (scaled size, not the base square).
    func shotSpriteBounds(for node: SKNode) -> CGRect {
        if let sprite = node as? SKSpriteNode {
            let width = sprite.size.width * abs(sprite.xScale)
            let height = sprite.size.height * abs(sprite.yScale)
            return CGRect(
                x: sprite.position.x - width * 0.5,
                y: sprite.position.y - height * 0.5,
                width: width,
                height: height
            )
        }
        let side = shotBaseSize * max(abs(node.xScale), abs(node.yScale))
        return CGRect(
            x: node.position.x - side * 0.5,
            y: node.position.y - side * 0.5,
            width: side,
            height: side
        )
    }
}
