import QuartzCore
import SpriteKit
import UIKit

extension CombatDeflectScene {
    // MARK: - Engine events

    func handle(_ events: [CombatDeflectEvent]) {
        for event in events {
            switch event {
            case let .throwOrb(id, letter, ring, travelSeconds):
                throwOrb(id: id, letter: letter, ring: ring, travelSeconds: travelSeconds)
            case let .speakLetter(trackID):
                // Phonetic tracks duck music + ambience loops for the clip's duration.
                SoundEffectsController.shared.play(trackID: trackID)
            case let .monsterHealthChanged(hp):
                animateMonsterHPBar()
                deflectDelegate?.combatDeflectSceneDidUpdateMonsterHP(
                    hp,
                    of: engine.config.monsterHP
                )
            case let .playerHealthChanged(health):
                deflectDelegate?.combatDeflectSceneDidUpdateHealth(health)
            case let .won(starsAwarded):
                finishWin(starsAwarded: starsAwarded)
            case .lost:
                finishLose()
            }
        }
    }

    /// Runs after a resolved orb when the fight is still going.
    func scheduleNextOrb() {
        guard !didEnd, engine.outcome == nil else { return }
        removeAction(forKey: nextOrbActionKey)
        run(
            .sequence([
                .wait(forDuration: interOrbDelaySeconds),
                .run { [weak self] in
                    guard let self else { return }
                    self.handle(self.engine.throwNextOrb())
                },
            ]),
            withKey: nextOrbActionKey
        )
    }

    // MARK: - Orbs

    func throwOrb(
        id: UUID,
        letter: String,
        ring: CombatDeflectRing,
        travelSeconds: Double
    ) {
        guard let playerNode, let enemyNode else { return }
        let travel = max(travelSeconds, 0.2)
        // A previous deflect may have left the player mirrored.
        setPlayerFacingLeft(false)
        let start = bodyCenter(of: enemyNode, height: enemySpriteHeight)
        let end = bodyCenter(of: playerNode, height: playerSpriteHeight)
        let control = inboundControlPoint(from: start, to: end)

        let node = makeOrbNode(letter: letter)
        node.position = start
        node.setScale(0.35)
        node.zPosition = Layer.orb
        node.name = "orb-\(id.uuidString)"
        addChild(node)

        activeOrb = OrbVisual(
            id: id,
            letter: letter,
            ring: ring,
            travelSeconds: travel,
            flightStartedAt: CACurrentMediaTime(),
            node: node
        )

        runFlight(
            on: node,
            start: start,
            control: control,
            end: end,
            duration: travel,
            startScale: 0.35,
            endScale: 1.15
        ) { [weak self] in
            // Reached the player untapped — same consequence as a wrong tap.
            self?.resolvePlayerHit()
        }
    }

    /// Grey circle with the letter on it. Placeholder art until real orb sprites land.
    func makeOrbNode(letter: String) -> SKNode {
        let circle = SKShapeNode(circleOfRadius: orbBaseSize * 0.5)
        circle.fillColor = UIColor.lightGray.withAlphaComponent(0.95)
        circle.strokeColor = .white
        circle.lineWidth = 2
        circle.isAntialiased = true

        let label = makeOutlinedLetter(
            letter,
            fontSize: orbBaseSize * 0.55,
            outline: .darkGray
        )
        label.zPosition = 1
        circle.addChild(label)
        return circle
    }

    func inboundControlPoint(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let mid = CGPoint(x: (start.x + end.x) * 0.5, y: (start.y + end.y) * 0.5)
        let lateral = CGFloat.random(in: -size.width * 0.42...size.width * 0.42)
        return CGPoint(x: mid.x + lateral, y: mid.y)
    }

    /// Follows a quadratic path while scaling, then calls `completion`.
    func runFlight(
        on node: SKNode,
        start: CGPoint,
        control: CGPoint,
        end: CGPoint,
        duration: TimeInterval,
        startScale: CGFloat,
        endScale: CGFloat,
        completion: @escaping () -> Void
    ) {
        let span = max(duration, 0.05)
        let follow = SKAction.customAction(withDuration: span) { [weak self] node, elapsed in
            guard let self else { return }
            let t = min(max(CGFloat(elapsed) / CGFloat(span), 0), 1)
            node.position = self.quadraticBezier(t: t, start: start, control: control, end: end)
            node.setScale(startScale + (endScale - startScale) * t)
        }
        node.run(
            .sequence([follow, .run(completion)]),
            withKey: orbFlightActionKey
        )
    }

    /// How far along its inbound flight the live orb is (`0…1`).
    func inboundProgress(of orb: OrbVisual) -> Double {
        let elapsed = CACurrentMediaTime() - orb.flightStartedAt
        return min(max(elapsed / max(orb.travelSeconds, 0.05), 0), 1)
    }

    func removeOrbNode() {
        activeOrb?.node.removeAllActions()
        activeOrb?.node.removeFromParent()
        activeOrb = nil
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !didEnd, engine.outcome == nil else { return }
        guard let touch = touches.first else { return }
        guard let ring = geometry.hitTest(touch.location(in: self)) else { return }

        switch engine.registerTap(ring: ring) {
        case .ignored:
            break
        case .correct(let ring):
            playDeflect(ring: ring)
        case .wrong:
            playWrongTap()
        }
    }

    /// Swing toward the tapped ring, then send the orb home at double speed.
    func playDeflect(ring: CombatDeflectRing) {
        guard let orb = activeOrb, let playerNode, let enemyNode else { return }
        if combatSprite != nil {
            playerNode.playOnce(
                name: playerSwingAnimationName,
                library: spriteLibrary,
                libraryID: playerCombatLibraryID
            )
            // Only one swing clip exists, so mirror it for the left-hand ring.
            // (`playOnce` resets scale from the clip; re-apply facing after.)
            setPlayerFacingLeft(ring == .northwest)
        }
        let progress = inboundProgress(of: orb)
        let letterPosition = orb.node.position
        // Flash + deflect cue land at 75% of the swing clip.
        let flashDelay = swingAnimationDurationSeconds() * 0.75
        run(
            .sequence([
                .wait(forDuration: flashDelay),
                .run { [weak self] in
                    guard let self else { return }
                    SoundEffectsController.shared.play(event: "deflect", from: self.playerFx)
                    self.playLightsaberDeflectFlash(letterPosition: letterPosition)
                },
            ]),
            withKey: deflectFlashActionKey
        )
        orb.node.removeAction(forKey: orbFlightActionKey)

        let start = letterPosition
        let end = bodyCenter(of: enemyNode, height: enemySpriteHeight)
        let mid = CGPoint(x: (start.x + end.x) * 0.5, y: (start.y + end.y) * 0.5)
        // Bend away from the ring the player tapped so the return reads as a deflection.
        let bend = size.width * 0.28 * (ring == .northwest ? -1 : ring == .northeast ? 1 : 0.12)
        let control = CGPoint(x: mid.x + bend, y: mid.y)
        let seconds = max(
            orb.travelSeconds * progress / deflectSpeedMultiplier,
            minimumReturnSeconds
        )

        runFlight(
            on: orb.node,
            start: start,
            control: control,
            end: end,
            duration: seconds,
            startScale: orb.node.xScale,
            endScale: 0.45
        ) { [weak self] in
            self?.resolveMonsterHit(at: end)
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

    /// Wrong ring: dash the orb into the player so the miss visibly lands.
    func playWrongTap() {
        guard let orb = activeOrb, let playerNode else { return }
        SoundEffectsController.shared.playCommon(event: "error")
        orb.node.removeAction(forKey: orbFlightActionKey)

        let start = orb.node.position
        let end = bodyCenter(of: playerNode, height: playerSpriteHeight)
        runFlight(
            on: orb.node,
            start: start,
            control: CGPoint(x: (start.x + end.x) * 0.5, y: (start.y + end.y) * 0.5),
            end: end,
            duration: wrongTapDashSeconds,
            startScale: orb.node.xScale,
            endScale: 1.15
        ) { [weak self] in
            self?.resolvePlayerHit()
        }
    }

    func resolveMonsterHit(at position: CGPoint) {
        guard !didEnd else { return }
        removeOrbNode()
        playExplosion(at: position)
        flashNode(enemyNode, color: .orange, actionKey: enemyFlashActionKey)

        let events = engine.registerOrbReachedMonster()
        handle(events)
        if !didEnd, engine.outcome == nil {
            scheduleNextOrb()
        }
    }

    func resolvePlayerHit() {
        guard !didEnd else { return }
        guard let playerNode else { return }
        let position = activeOrb?.node.position
            ?? bodyCenter(of: playerNode, height: playerSpriteHeight)
        removeOrbNode()
        playDamage(at: position)

        let events = engine.registerOrbHitPlayer()
        handle(events)
        if !didEnd, engine.outcome == nil {
            scheduleNextOrb()
        }
    }
}
