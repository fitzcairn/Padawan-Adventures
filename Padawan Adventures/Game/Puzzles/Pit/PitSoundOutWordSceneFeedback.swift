import SpriteKit
import UIKit

extension PitSoundOutWordScene {
    // MARK: - Evaluate drop

    func evaluate(candidateIndex: Int) {
        guard candidateNodes.indices.contains(candidateIndex) else {
            isUserInteractionEnabled = true
            return
        }
        let tile = candidateNodes[candidateIndex]
        guard let idString = tile.userData?["id"] as? String,
              let id = UUID(uuidString: idString) else {
            isUserInteractionEnabled = true
            return
        }
        let grapheme = (tile.userData?["grapheme"] as? String) ?? ""
        let letterIndex = engine.currentIndex ?? 0
        let outcome = engine.drop(choiceID: id, isPlacementValid: true)
        switch outcome {
        case .accepted:
            handleAccepted(tile: tile, letterIndex: letterIndex, grapheme: grapheme)
        case .rejected:
            handleRejected(tile: tile)
        }
    }

    func handleAccepted(tile: SKNode, letterIndex: Int, grapheme: String) {
        playDucked(
            event: "correct",
            from: SoundEffectsController.shared.commonFx.merging(pitFx)
        )
        flashGrapheme(
            at: letterIndex,
            apply: platformCorrectTint,
            clear: .white,
            count: 1
        )

        let keep = tile
        for node in candidateNodes where node !== keep {
            node.run(SKAction.sequence([
                SKAction.fadeOut(withDuration: 0.2),
                SKAction.removeFromParent(),
            ]))
        }
        keep.zPosition = Self.landedTilesZ
        landedTileNodes.append(keep)
        candidateNodes = []

        revealGrapheme(on: keep, grapheme) { [weak self] in
            guard let self else { return }
            if self.engine.isSolved {
                self.finishWon()
            } else {
                self.beginStep()
            }
        }
    }

    /// Crossfades the play symbol into the grapheme that tile was hiding.
    func revealGrapheme(on tile: SKNode, _ grapheme: String, completion: (() -> Void)? = nil) {
        let play = MinigamePlaySoundIcon.find(in: tile)
        if let play { MinigamePlaySoundIcon.cancelPulse(play) }

        let stack = OutlinedLetterFactory.make(
            text: grapheme,
            fontSize: max(geometry.tileSide * 0.55, 18),
            disablesInteraction: true
        )
        stack.name = Self.graphemeGlyphName
        // Face centre — do not inherit the play symbol's optical x-nudge.
        stack.position = .zero
        stack.zPosition = 1
        stack.alpha = 0
        tile.childNode(withName: Self.graphemeGlyphName)?.removeFromParent()
        tile.addChild(stack)

        let duration = Self.letterRevealDuration
        if let play {
            play.run(SKAction.sequence([
                SKAction.fadeOut(withDuration: duration),
                SKAction.removeFromParent(),
            ]))
        }
        stack.run(SKAction.fadeIn(withDuration: duration)) {
            completion?()
        }
    }

    func handleRejected(tile: SKNode) {
        playDucked(
            event: "error",
            from: SoundEffectsController.shared.commonFx.merging(pitFx)
        )
        flashOverlay(on: tile, color: platformWrongTint) { [weak self] in
            guard let self else { return }
            // Bounce Kam home and reshuffle the blank tiles in parallel.
            var pending = 2
            let finish: () -> Void = { [weak self] in
                guard let self else { return }
                pending -= 1
                guard pending == 0 else { return }
                self.playerFacingLeft = false
                self.resumePlayerIdle()
                if let grapheme = self.engine.currentGrapheme,
                   let trackID = self.engine.nameTrackID(for: grapheme) {
                    SoundEffectsController.shared.play(trackID: trackID)
                }
                self.isUserInteractionEnabled = true
            }
            self.isJumping = true
            self.jumpPlayer(to: self.dragStartPosition) {
                self.isJumping = false
                finish()
            }
            self.shuffleAndAnimateCandidates(completion: finish)
        }
    }

    /// Reorders the active set, rolls fresh jitter, and slides every tile into place.
    func shuffleAndAnimateCandidates(completion: (() -> Void)? = nil) {
        guard let stepIndex = engine.currentIndex, !candidateNodes.isEmpty else {
            completion?()
            return
        }
        engine.shuffleCurrentChoices()

        var nodesByID: [UUID: SKNode] = [:]
        for node in candidateNodes {
            guard let idString = node.userData?["id"] as? String,
                  let id = UUID(uuidString: idString) else { continue }
            nodesByID[id] = node
        }

        let geo = geometry
        let choices = engine.currentChoices
        let count = choices.count
        let jitters = geo.candidateJitters(step: stepIndex, count: count, using: &placementRNG)
        var reordered: [SKNode] = []
        reordered.reserveCapacity(count)

        for (index, choice) in choices.enumerated() {
            guard let node = nodesByID[choice.id] else { continue }
            let jitter = jitters[index]
            let center = geo.candidateCenter(step: stepIndex, candidate: index, count: count)
            let target = CGPoint(x: center.x + jitter.x, y: center.y + jitter.y)

            node.name = "candidate:\(index)"
            if node.userData == nil { node.userData = NSMutableDictionary() }
            node.userData?["index"] = index
            node.userData?["count"] = count
            node.userData?["step"] = stepIndex
            node.userData?["jitterX"] = jitter.x
            node.userData?["jitterY"] = jitter.y

            node.removeAction(forKey: "candidateShuffle")
            let move = SKAction.move(to: target, duration: Self.shuffleDuration)
            move.timingMode = .easeInEaseOut
            node.run(move, withKey: "candidateShuffle")
            reordered.append(node)
        }
        candidateNodes = reordered

        removeAction(forKey: Self.shuffleActionKey)
        run(
            SKAction.sequence([
                SKAction.wait(forDuration: Self.shuffleDuration),
                SKAction.run { completion?() },
            ]),
            withKey: Self.shuffleActionKey
        )
    }

    func flashOverlay(on node: SKNode, color: UIColor, completion: @escaping () -> Void) {
        let side = geometry.tileSide
        let overlay = SKShapeNode(rectOf: CGSize(width: side, height: side * 0.6), cornerRadius: 4)
        overlay.fillColor = color.withAlphaComponent(0.55)
        overlay.strokeColor = .clear
        overlay.zPosition = SceneLayer.overlay
        overlay.name = "flashOverlay"
        node.addChild(overlay)
        let flash = SKAction.doubleFlash(
            count: 1,
            apply: { overlay.alpha = 1 },
            clear: { overlay.alpha = 0 }
        )
        overlay.run(flash) {
            overlay.removeFromParent()
            completion()
        }
    }

    // MARK: - Jump / win

    func jumpPlayer(
        to target: CGPoint,
        landAnimation: String? = nil,
        completion: @escaping () -> Void
    ) {
        guard let playerNode else {
            completion()
            return
        }
        playDucked(event: "jump", from: pitFx)
        let start = playerNode.position
        playJumpAnimation(toward: target)
        let arcHeight = max(
            geometry.tileSide * 1.1,
            hypot(target.x - start.x, target.y - start.y) * 0.35
        )
        let control = CGPoint(
            x: (start.x + target.x) * 0.5,
            y: max(start.y, target.y) + arcHeight
        )
        let duration = Self.jumpDuration
        let action = SKAction.customAction(withDuration: duration) { [weak self] _, elapsedTime in
            guard let self, let playerNode = self.playerNode else { return }
            let t = min(max(elapsedTime / CGFloat(duration), 0), 1)
            playerNode.position = PitArenaLayout.jumpPoint(
                t: t,
                start: start,
                control: control,
                end: target
            )
        }
        playerNode.run(action) { [weak self] in
            guard let self, let playerNode = self.playerNode else {
                completion()
                return
            }
            playerNode.position = target
            if let landAnimation,
               self.spriteLibrary.animation(id: Self.playerLibraryID, named: landAnimation) != nil {
                self.playPlayerLoop(landAnimation)
            } else {
                self.resumePlayerIdle()
            }
            completion()
        }
    }

    func finishWon() {
        guard !didEnd else { return }
        didEnd = true
        isUserInteractionEnabled = false
        let exit = CGPoint(x: geometry.rightPadRect.midX, y: geometry.rightPadRect.midY)
        isJumping = true
        jumpPlayer(to: exit, landAnimation: "celebrate_down") { [weak self] in
            guard let self else { return }
            self.isJumping = false
            let stars = self.engine.targetGraphemes.count
            var actions: [SKAction] = []
            actions.append(SKAction.run { [weak self] in
                guard let self else { return }
                self.playDucked(
                    event: "win",
                    from: SoundEffectsController.shared.commonFx.merging(self.pitFx)
                )
            })
            actions.append(SKAction.run { [weak self] in
                self?.soundOutDelegate?.pitSoundOutWordSceneDidWin(starsAwarded: stars)
            })
            self.run(SKAction.sequence(actions), withKey: Self.winSoundActionKey)
        }
    }
}
