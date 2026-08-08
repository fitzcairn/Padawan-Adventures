import SpriteKit
import UIKit

extension PitBridgeScene {
    func handleCorrectDrop(
        node: SKNode,
        id: UUID,
        slotIndex: Int,
        won: Bool,
        letter: String,
        maskedPrompt: String
    ) {
        let target = geometry.slotCenter(slotIndex)
        node.position = target
        // Use the pre-accept mask: `accept` already advanced to the next word.
        setBlankLetterText(letter, maskedPrompt: maskedPrompt)
        flashBlankLetter(color: platformCorrectTint) { [weak self] in
            // Keep the filled letter green until the next round replaces the prompt.
            self?.setBlankLetterFillColor(self?.platformCorrectTint ?? .systemGreen)
        }
        flashOverlay(on: node, color: platformCorrectTint) { [weak self] in
            guard let self else { return }
            self.playCorrectLetterCues(letter: letter) {
                self.playDucked(
                    event: "correct",
                    from: SoundEffectsController.shared.commonFx.merging(self.pitFx)
                )
                if let label = node.childNode(withName: "letterLabel") {
                    label.run(SKAction.sequence([
                        SKAction.fadeOut(withDuration: 0.3),
                        SKAction.removeFromParent(),
                    ]))
                }
                self.slotBoxNode?.removeFromParent()
                self.slotBoxNode = nil
                node.zPosition = Self.placedTilesZ
                self.trayNodes.removeValue(forKey: id)
                self.placedTileNodes.append(node)
                let leftovers = Array(self.trayNodes.values)
                self.trayNodes = [:]
                for other in leftovers {
                    other.run(SKAction.sequence([
                        SKAction.fadeOut(withDuration: 0.2),
                        SKAction.removeFromParent(),
                    ]))
                }
                self.isJumping = true
                self.jumpPlayer(to: target) {
                    self.isJumping = false
                    if won {
                        self.finishWon()
                    } else {
                        self.beginRound()
                    }
                }
            }
        }
    }

    func handleIncorrectDrop(node: SKNode, letter: String) {
        setBlankLetterText(letter)
        flashBlankLetter(color: platformWrongTint) { [weak self] in
            self?.setBlankLetterText("_")
            self?.setBlankLetterFillColor(.white)
        }
        flashOverlay(on: node, color: platformWrongTint) { [weak self] in
            guard let self else { return }
            self.playDucked(
                event: "error",
                from: SoundEffectsController.shared.commonFx.merging(self.pitFx)
            )
            self.springBack(node, to: self.dragStartPosition) {
                self.playWordSound {
                    self.isUserInteractionEnabled = true
                }
            }
        }
    }

    func springBack(_ node: SKNode, to position: CGPoint, completion: (() -> Void)? = nil) {
        let action = SKAction.move(to: position, duration: Self.springBackDuration)
        action.timingMode = .easeOut
        node.run(
            .sequence([
                action,
                .run {
                    node.zPosition = Self.trayTilesZ
                    completion?()
                },
            ]),
            withKey: "springBack"
        )
    }

    /// Smoothly pulls a near-miss drop into the dashed slot before feedback runs.
    func snapIntoSlot(_ node: SKNode, to position: CGPoint, completion: @escaping () -> Void) {
        let distance = hypot(node.position.x - position.x, node.position.y - position.y)
        guard distance > 1 else {
            node.position = position
            completion()
            return
        }
        let action = SKAction.move(to: position, duration: Self.snapIntoSlotDuration)
        action.timingMode = .easeOut
        node.run(
            .sequence([
                action,
                .run(completion),
            ]),
            withKey: Self.snapIntoSlotActionKey
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
        let exit = CGPoint(x: geometry.rightPadRect.midX, y: geometry.bridgeLineY)
        isJumping = true
        jumpPlayer(to: exit, landAnimation: "celebrate_down") { [weak self] in
            guard let self else { return }
            self.isJumping = false
            let stars = self.engine.wordCount
            var actions: [SKAction] = []
            actions.append(SKAction.run { [weak self] in
                guard let self else { return }
                self.playDucked(
                    event: "win",
                    from: SoundEffectsController.shared.commonFx.merging(self.pitFx)
                )
            })
            actions.append(SKAction.run { [weak self] in
                self?.bridgeDelegate?.pitBridgeSceneDidWin(starsAwarded: stars)
            })
            self.run(SKAction.sequence(actions), withKey: Self.winSoundActionKey)
        }
    }
}
