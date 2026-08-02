import SpriteKit
import UIKit

extension PitScene {
    func addPlayer(at position: CGPoint) {
        playerSprite = nil
        playerFacingLeft = false
        let height = playerDisplayHeight

        if let config = playerSpriteConfig,
           spriteLibrary.animation(id: Self.playerLibraryID, named: "idle_right") != nil
            || spriteLibrary.animation(id: Self.playerLibraryID, named: "idle_down") != nil {
            let sprite = AnimatedSpriteNode(size: CGSize(width: height, height: height))
            sprite.fitHeight(height)
            // Above pad / letter floor tiles (local tile sort stays small; world depthSort is huge).
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

    var playerDisplayHeight: CGFloat {
        if let config = playerSpriteConfig {
            return max(
                PlaceholderFactory.spriteDisplayHeight(isoConfig: isoConfig, spriteConfig: config),
                48
            )
        }
        return max(letterRadius * 2.4, 48)
    }

    func resumePlayerIdle() {
        guard playerSprite != nil else { return }
        let preferred = playerFacingLeft ? "idle_left" : "idle_right"
        let name: String
        if spriteLibrary.animation(id: Self.playerLibraryID, named: preferred) != nil {
            name = preferred
        } else {
            name = "idle_down"
        }
        playPlayerLoop(name)
    }

    func playPlayerLoop(_ name: String) {
        guard let playerSprite else { return }
        playerSprite.play(name: name, library: spriteLibrary, libraryID: Self.playerLibraryID)
        playerSprite.fitHeight(playerDisplayHeight)
    }

    func playJumpAnimation(toward target: CGPoint) {
        guard let playerSprite, let playerNode else { return }
        playerFacingLeft = target.x < playerNode.position.x - 0.5
        let name = playerFacingLeft ? "jump_left" : "jump_right"
        playerSprite.playOnce(name: name, library: spriteLibrary, libraryID: Self.playerLibraryID)
        playerSprite.fitHeight(playerDisplayHeight)
    }
    // MARK: - Events / audio

    func playWordSound() {
        removeAction(forKey: Self.connectedSoundActionKey)
        let trackID = engine.targetSoundTrackID
        guard !trackID.isEmpty else { return }
        SoundEffectsController.shared.play(trackID: trackID)
    }

    /// Progressive prefix cue only — word sound is reserved for incorrect jumps / open / win.
    func playConnectedPrefixSound(_ prefix: String, then completion: (() -> Void)? = nil) {
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

    func finishWon() {
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
                from: SoundEffectsController.shared.commonFx.merging(self.pitFx)
            )
        })
        let word = engine.targetWord
        let stars = engine.targetWord.count
        actions.append(SKAction.run { [weak self] in
            self?.pitDelegate?.pitSceneDidWin(word: word, starsAwarded: stars)
        })
        run(SKAction.sequence(actions), withKey: Self.winSoundActionKey)
    }

    // MARK: - Touch / jump

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !didEnd, !isJumping, let touch = touches.first, let playerNode else { return }
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

    func letterNode(at point: CGPoint) -> SKNode? {
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

    func jumpPlayer(
        to target: CGPoint,
        landAnimation: String? = nil,
        completion: @escaping () -> Void
    ) {
        guard let playerNode else {
            completion()
            return
        }
        SoundEffectsController.shared.play(event: "jump", from: pitFx)
        let start = playerNode.position
        playJumpAnimation(toward: target)
        let arcHeight = max(letterRadius * 2.2, hypot(target.x - start.x, target.y - start.y) * 0.35)
        let control = CGPoint(
            x: (start.x + target.x) * 0.5,
            y: max(start.y, target.y) + arcHeight
        )
        let duration = Self.jumpDuration
        let action = SKAction.customAction(withDuration: duration) { [weak self] _, elapsedTime in
            guard let self, let playerNode = self.playerNode else { return }
            let linearT = min(max(elapsedTime / CGFloat(duration), 0), 1)
            // Smoothstep ease-in / ease-out.
            let t = linearT * linearT * (3 - 2 * linearT)
            let oneMinus = 1 - t
            let x = oneMinus * oneMinus * start.x + 2 * oneMinus * t * control.x + t * t * target.x
            let y = oneMinus * oneMinus * start.y + 2 * oneMinus * t * control.y + t * t * target.y
            playerNode.position = CGPoint(x: x, y: y)
        }
        playerNode.run(action) { [weak self] in
            guard let self, let playerNode = self.playerNode else {
                completion()
                return
            }
            playerNode.position = target
            // Keep Kam above the landed floor tile (letter platforms sit at SceneLayer.letterPlatform).
            playerNode.zPosition = Self.playerZ
            if let landAnimation,
               self.spriteLibrary.animation(id: Self.playerLibraryID, named: landAnimation) != nil {
                self.playPlayerLoop(landAnimation)
            } else {
                self.resumePlayerIdle()
            }
            completion()
        }
    }

    func flashWrong(id: UUID, completion: @escaping () -> Void) {
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

    // MARK: - Test seams

    func touchesBeganForTesting(at location: CGPoint) {
        touchesBegan(Set([SceneTestTouch(location: location)]), with: nil)
    }
}
