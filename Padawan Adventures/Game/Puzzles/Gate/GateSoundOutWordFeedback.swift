import SpriteKit
import UIKit

extension GateSoundOutWordScene {
    // MARK: - Round flow

    /// Opens the round: say the whole word, then prompt the first grapheme.
    func beginRound() {
        updatePromptColors()
        inputLocked = true
        playWordSound()
        let wordDuration = SoundEffectsController.shared.cueDuration(of: engine.wordTrackID)
        removeAction(forKey: Self.promptActionKey)
        run(
            SKAction.sequence([
                SKAction.wait(forDuration: wordDuration),
                SKAction.run { [weak self] in
                    self?.promptCurrentGrapheme(fadeInChoices: true)
                },
            ]),
            withKey: Self.promptActionKey
        )
    }

    /// Flashes the active grapheme white/orange (leaving orange), says its name, and fades
    /// the matching capacitor set in at the same time.
    func promptCurrentGrapheme(fadeInChoices: Bool) {
        guard let index = engine.currentIndex, let grapheme = engine.currentGrapheme else { return }

        if fadeInChoices {
            layoutCurrentChoiceSet(fadeIn: true)
        }
        playGraphemeName(grapheme)

        inputLocked = true
        removeAction(forKey: Self.promptActionKey)
        let flash = SKAction.doubleFlash(
            period: Self.promptFlashPeriod,
            count: 2,
            apply: { [weak self] in
                guard let self else { return }
                self.setPromptColor(at: index, color: self.promptActiveColor)
            },
            clear: { [weak self] in
                guard let self else { return }
                self.setPromptColor(at: index, color: self.promptPendingColor)
            }
        )
        run(
            SKAction.sequence([
                flash,
                SKAction.run { [weak self] in
                    guard let self else { return }
                    // Settle on orange: this is the grapheme the player is hunting for.
                    self.setPromptColor(at: index, color: self.promptActiveColor)
                    self.inputLocked = false
                },
            ]),
            withKey: Self.promptActionKey
        )
    }

    /// Lays the active set out bottom-middle with equal spacing, blank faced and lightly tinted.
    func layoutCurrentChoiceSet(fadeIn: Bool) {
        clearChoiceNodes()
        let choices = engine.currentChoices
        guard !choices.isEmpty else { return }
        // The engine guarantees this; log loudly if a future change breaks solvability.
        assert(
            engine.currentChoicesIncludeAnswer,
            "sound-out-word gate is missing answer '\(engine.currentGrapheme ?? "")'"
        )

        let positions = choiceRowPositions(count: choices.count)
        for (index, choice) in choices.enumerated() {
            let node = makeCapacitorNode(
                name: "choice:\(choice.id.uuidString)",
                diameter: laidOutDiameter,
                grapheme: nil
            )
            node.position = positions[index]
            applyCapacitorTint(
                to: node,
                color: choiceTints[choice.tintIndex % choiceTints.count],
                blend: choiceTintBlend
            )
            node.alpha = fadeIn ? 0 : 1
            addChild(node)
            choiceNodes[choice.id] = node
            choiceHome[choice.id] = positions[index]
            if fadeIn {
                node.run(SKAction.fadeIn(withDuration: Self.setFadeDuration))
            }
        }
    }

    func clearChoiceNodes() {
        for node in choiceNodes.values {
            node.removeFromParent()
        }
        choiceNodes = [:]
        choiceHome = [:]
    }

    // MARK: - Placement outcomes

    /// Right grapheme, right place: chime, flash the word letter green, reveal the glyph on
    /// the capacitor, wire it to its neighbour, then move on to the next grapheme.
    func runAcceptedPlacement(choiceID: UUID) {
        guard let node = choiceNodes[choiceID] else { return }
        let index = max(engine.placedCount - 1, 0)
        guard let grapheme = engine.grapheme(at: index) else { return }

        inputLocked = true
        // Promote the dragged capacitor into the placed chain and drop the rest of the set.
        choiceNodes[choiceID] = nil
        choiceHome[choiceID] = nil
        fadeOutRemainingChoices()
        node.name = "placed:\(index)"
        node.zPosition = 20
        clearCapacitorTint(on: node)
        placedNodes.append(node)
        placedFractions.append(playAreaFraction(of: node.position))

        playCorrectSound()
        revealGrapheme(on: node, grapheme)
        updateConnectors()

        let flash = SKAction.doubleFlash(
            period: Self.solvedFlashPeriod,
            count: 2,
            apply: { [weak self] in
                guard let self else { return }
                self.setPromptColor(at: index, color: self.promptSolvedFlashColor)
            },
            clear: { [weak self] in
                guard let self else { return }
                self.setPromptColor(at: index, color: self.promptPendingColor)
            }
        )
        let chimeDuration = SoundEffectsController.shared.cueDuration(of: correctSoundTrackID)
        removeAction(forKey: Self.feedbackActionKey)
        run(
            SKAction.sequence([
                SKAction.group([
                    flash,
                    SKAction.wait(forDuration: chimeDuration),
                ]),
                SKAction.run { [weak self] in
                    guard let self else { return }
                    self.setPromptColor(at: index, color: self.promptPendingColor)
                    if self.engine.isSolved {
                        self.beginWinSequence()
                    } else {
                        self.promptCurrentGrapheme(fadeInChoices: true)
                    }
                },
            ]),
            withKey: Self.feedbackActionKey
        )
    }

    /// Eases a near-miss drop into the closest legal play-area spot, then resolves accept/reject.
    func runAssistedPlacement(choiceID: UUID, to target: CGPoint) {
        guard let node = choiceNodes[choiceID] else { return }
        inputLocked = true
        node.run(
            SKAction.sequence([
                SKAction.move(to: target, duration: Self.returnHomeDuration)
                    .withTimingMode(.easeInEaseOut),
                SKAction.run { [weak self] in
                    self?.resolveDrop(choiceID: choiceID, isPlacementValid: true)
                },
            ])
        )
    }

    /// Wrong grapheme, or the right one in the wrong place: buzz, flash red, then reshuffle
    /// the whole set with a slide into the new order.
    func runRejectedPlacement(choiceID: UUID) {
        guard let node = choiceNodes[choiceID] else { return }
        inputLocked = true
        playErrorSound()

        let flash = SKAction.doubleFlash(
            period: Self.wrongFlashPeriod,
            count: 2,
            apply: { [weak self] in
                guard let self else { return }
                self.applyCapacitorTint(
                    to: node,
                    color: self.capacitorWrongFlash,
                    blend: self.capacitorTintBlend
                )
            },
            clear: { [weak self] in
                self?.restoreChoiceTint(choiceID: choiceID)
            }
        )
        node.run(
            SKAction.sequence([
                flash,
                SKAction.run { [weak self] in
                    guard let self else { return }
                    self.restoreChoiceTint(choiceID: choiceID)
                    self.shuffleAndAnimateChoices()
                },
            ])
        )
    }

    /// Shuffles the active set and slides every capacitor (including the rejected one) home.
    func shuffleAndAnimateChoices() {
        engine.shuffleCurrentChoices()
        let choices = engine.currentChoices
        let positions = choiceRowPositions(count: choices.count)
        for (index, choice) in choices.enumerated() {
            let home = positions[index]
            choiceHome[choice.id] = home
            guard let node = choiceNodes[choice.id] else { continue }
            node.zPosition = 20
            node.run(
                SKAction.move(to: home, duration: Self.shuffleDuration)
                    .withTimingMode(.easeInEaseOut)
            )
        }
        removeAction(forKey: Self.feedbackActionKey)
        run(
            SKAction.sequence([
                SKAction.wait(forDuration: Self.shuffleDuration),
                SKAction.run { [weak self] in self?.inputLocked = false },
            ]),
            withKey: Self.feedbackActionKey
        )
    }

    func restoreChoiceTint(choiceID: UUID) {
        guard let node = choiceNodes[choiceID],
              let choice = engine.currentChoices.first(where: { $0.id == choiceID }) else {
            return
        }
        applyCapacitorTint(
            to: node,
            color: choiceTints[choice.tintIndex % choiceTints.count],
            blend: choiceTintBlend
        )
    }

    func animateChoiceHome(_ choiceID: UUID) {
        guard let node = choiceNodes[choiceID], let home = choiceHome[choiceID] else { return }
        node.run(SKAction.move(to: home, duration: 0.15).withTimingMode(.easeOut))
    }

    /// Decoys from the finished set drift out as the next set arrives.
    func fadeOutRemainingChoices() {
        let leaving = choiceNodes.values
        choiceNodes = [:]
        choiceHome = [:]
        for node in leaving {
            node.run(SKAction.sequence([
                SKAction.fadeOut(withDuration: Self.setFadeDuration),
                SKAction.removeFromParent(),
            ]))
        }
    }

    // MARK: - Connectors

    func playAreaFraction(of point: CGPoint) -> CGPoint {
        let rect = playAreaRect
        guard rect.width > 0, rect.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        return CGPoint(
            x: (point.x - rect.minX) / rect.width,
            y: (point.y - rect.minY) / rect.height
        )
    }

    /// Left endpoint → placed capacitors → right endpoint once the word is complete.
    func updateConnectors() {
        clearConnectorSegments()
        defer { syncArcLoopWithConnectors() }
        guard !didEnd, let leftEndpointNode, let rightEndpointNode else { return }
        guard let first = placedNodes.first else { return }

        addConnectorLine(from: leftEndpointNode.position, to: first.position)
        for index in 1..<max(placedNodes.count, 1) {
            addConnectorLine(
                from: placedNodes[index - 1].position,
                to: placedNodes[index].position
            )
        }

        guard engine.isSolved, let last = placedNodes.last else { return }
        addConnectorLine(from: last.position, to: rightEndpointNode.position)
        applyCapacitorTint(to: leftEndpointNode, color: capacitorSolvedTint, blend: capacitorTintBlend)
        applyCapacitorTint(to: rightEndpointNode, color: capacitorSolvedTint, blend: capacitorTintBlend)
        for node in placedNodes {
            applyCapacitorTint(to: node, color: capacitorSolvedTint, blend: capacitorTintBlend)
        }
    }
}
