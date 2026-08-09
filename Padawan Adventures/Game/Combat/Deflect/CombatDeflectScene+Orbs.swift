import QuartzCore
import SpriteKit
import UIKit

extension CombatDeflectScene {
    // MARK: - Engine events

    func handle(_ events: [CombatDeflectEvent]) {
        for event in events {
            switch event {
            case let .throwOrb(id, letter, word, sfx, ring, travelSeconds):
                throwOrb(
                    id: id,
                    letter: letter,
                    word: word,
                    sfx: sfx,
                    ring: ring,
                    travelSeconds: travelSeconds
                )
            case let .speakWord(trackID):
                // Word tracks duck music + ambience loops for the clip's duration.
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
        word: String,
        sfx: String,
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

        let built = makeOrbNode(letter: letter, word: word)
        let node = built.node
        node.position = start
        node.setScale(0.35)
        node.zPosition = Layer.orb
        node.name = "orb-\(id.uuidString)"
        addChild(node)

        activeOrb = OrbVisual(
            id: id,
            letter: letter,
            word: word,
            sfx: sfx,
            ring: ring,
            travelSeconds: travel,
            flightStartedAt: CACurrentMediaTime(),
            node: node,
            projectileWidth: built.projectileWidth,
            wordNode: built.wordNode,
            pathStart: start,
            pathControl: control,
            pathEnd: end
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
            // Reached the player untapped — costs a heart.
            self?.resolvePlayerHit()
        }
    }

    struct OrbBuild {
        let node: SKNode
        let wordNode: SKNode
        let projectileWidth: CGFloat
    }

    /// The masked word centered on the enemy's animated projectile. The art is scaled to
    /// the word rather than the other way round, so long words stay legible. Falls back
    /// to a dark disc when the enemy has no projectile sprite.
    func makeOrbNode(letter: String, word: String) -> OrbBuild {
        let root = SKNode()
        let built = makeMaskedWordNode(
            word: word,
            grapheme: letter,
            fontSize: orbWordFontSize
        )
        let fit = CombatDeflectOrbWord.fit(
            wordWidth: built.width,
            baseWidth: orbBaseSize * Self.projectileSpriteScale,
            maxWidth: maxProjectileWidth,
            fitFraction: Self.orbWordFitFraction
        )

        if let projectile = makeProjectileNode(width: fit.projectileWidth) {
            root.addChild(projectile)
        } else {
            let backing = SKShapeNode(circleOfRadius: fit.projectileWidth * 0.55)
            backing.fillColor = UIColor.black.withAlphaComponent(0.55)
            backing.strokeColor = UIColor.white.withAlphaComponent(0.85)
            backing.lineWidth = 2
            backing.isAntialiased = true
            root.addChild(backing)
        }

        built.node.setScale(fit.wordScale)
        built.node.zPosition = 1
        root.addChild(built.node)
        return OrbBuild(
            node: root,
            wordNode: built.node,
            projectileWidth: fit.projectileWidth
        )
    }

    /// Looping projectile clip sized to wrap the masked word.
    private func makeProjectileNode(width: CGFloat) -> AnimatedSpriteNode? {
        guard let projectileSprite,
              spriteLibrary.animation(id: projectileSprite.id, named: "fly") != nil else {
            return nil
        }
        let node = AnimatedSpriteNode(size: CGSize(width: width, height: width))
        // Characters anchor at texture-top so their feet stay on the node position; an orb
        // wants its middle there instead. The V-correcting negative yScale still resolves
        // because it mirrors about the same center.
        node.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        node.play(name: "fly", library: spriteLibrary, libraryID: projectileSprite.id)
        // After `play` the texture exists, so `fitWidth` can lock pixels-to-points.
        node.fitWidth(width)
        return node
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

    /// Where the inbound orb will be `seconds` from now.
    func predictedOrbCenter(of orb: OrbVisual, after seconds: TimeInterval) -> CGPoint {
        let elapsed = CACurrentMediaTime() - orb.flightStartedAt + seconds
        let t = CGFloat(min(max(elapsed / max(orb.travelSeconds, 0.05), 0), 1))
        return quadraticBezier(
            t: t,
            start: orb.pathStart,
            control: orb.pathControl,
            end: orb.pathEnd
        )
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
        let point = touch.location(in: self)
        guard let ring = geometry.hitTest(point) else {
            replayActiveOrbWord(at: point)
            return
        }
        // Wrong-letter feedback owns the blank briefly; ignore ring taps until it clears.
        guard !isWrongLetterFeedbackActive else { return }

        switch engine.registerTap(ring: ring) {
        case .ignored:
            break
        case .correct(let ring):
            playDeflect(ring: ring)
        case .wrong(let ring):
            guard let letter = letter(for: ring) else { return }
            playWrongTap(letter: letter)
        }
    }

    /// Tapping the orb itself replays its word. It never resolves the orb, so it is free:
    /// no deflect, no lost heart, no engine call.
    func replayActiveOrbWord(at point: CGPoint) {
        guard let orb = activeOrb, engine.activeOrb?.isResolved == false else { return }
        let radius = orb.projectileWidth * 0.5 * abs(orb.node.xScale)
        let dx = point.x - orb.node.position.x
        let dy = point.y - orb.node.position.y
        guard dx * dx + dy * dy <= radius * radius else { return }
        let now = CACurrentMediaTime()
        guard now - lastWordReplayAt >= wordReplayCooldownSeconds else { return }
        lastWordReplayAt = now

        SoundEffectsController.shared.play(trackID: orb.sfx)
        // `runFlight` rewrites the root's scale every frame, so pulse the word child.
        // `scale(by:)` is relative, so it composes with the clamped `wordScale`.
        orb.wordNode.removeAction(forKey: orbWordPulseActionKey)
        orb.wordNode.run(
            .sequence([
                .scale(by: 1.15, duration: 0.09),
                .scale(by: 1 / 1.15, duration: 0.09),
            ]),
            withKey: orbWordPulseActionKey
        )
    }

    /// Swing toward the tapped ring, then send the orb home at double speed.
    func playDeflect(ring: CombatDeflectRing) {
        guard let orb = activeOrb, let playerNode, let enemyNode else { return }
        revealOrbAnswerLetter(on: orb)
        if combatSprite != nil {
            playerNode.playOnce(
                name: playerSwingAnimationName,
                library: spriteLibrary,
                libraryID: playerCombatLibraryID
            )
            // Only one swing clip exists, so mirror it for rings on the left side.
            // (`playOnce` resets scale from the clip; re-apply facing after.)
            setPlayerFacingLeft(cos(geometry.angle(for: ring)) < 0)
        }
        let progress = inboundProgress(of: orb)
        let projectilePosition = orb.node.position
        // Flash + deflect cue land at 20% of the swing clip.
        let flashDelay = swingAnimationDurationSeconds() * 0.2
        run(
            .sequence([
                .wait(forDuration: flashDelay),
                .run { [weak self] in
                    guard let self else { return }
                    SoundEffectsController.shared.play(event: "deflect", from: self.playerFx)
                    self.playLightsaberDeflectFlash(
                        ring: ring,
                        projectilePosition: projectilePosition
                    )
                },
            ]),
            withKey: deflectFlashActionKey
        )
        orb.node.removeAction(forKey: orbFlightActionKey)

        let start = projectilePosition
        let end = bodyCenter(of: enemyNode, height: enemySpriteHeight)
        let mid = CGPoint(x: (start.x + end.x) * 0.5, y: (start.y + end.y) * 0.5)
        // Bend away from the ring the player tapped so the return reads as a deflection.
        let lateral = cos(geometry.angle(for: ring))
        let bendFactor: CGFloat = abs(lateral) < 0.08 ? 0.12 : (lateral < 0 ? -1 : 1)
        let bend = size.width * 0.28 * bendFactor
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

    /// Wrong ring: show the tapped letter in red on the blank, play error, flash it,
    /// restore the blank, and replay the word. The inbound flight keeps going so the
    /// player can keep trying until the orb lands or they deflect it.
    func playWrongTap(letter: String) {
        guard let orb = activeOrb, !isWrongLetterFeedbackActive else { return }
        guard let presented = presentWrongOrbLetter(letter, on: orb) else { return }
        isWrongLetterFeedbackActive = true
        let orbID = orb.id
        SoundEffectsController.shared.playCommon(event: "error")
        flashPresentedWrongOrbLetter(
            presented.letterNode,
            blanks: presented.blanks,
            on: orb
        ) { [weak self] in
            guard let self else { return }
            self.isWrongLetterFeedbackActive = false
            guard let live = self.activeOrb, live.id == orbID,
                  self.engine.activeOrb?.isResolved == false else { return }
            SoundEffectsController.shared.play(trackID: live.sfx)
            live.wordNode.removeAction(forKey: self.orbWordPulseActionKey)
            live.wordNode.run(
                .sequence([
                    .scale(by: 1.15, duration: 0.09),
                    .scale(by: 1 / 1.15, duration: 0.09),
                ]),
                withKey: self.orbWordPulseActionKey
            )
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
        isWrongLetterFeedbackActive = false
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
