import SpriteKit

extension GateGraphemeMatchScene {
    // MARK: - Events

    func handle(_ event: GateGraphemeMatchEngineEvent) {
        switch event {
        case .playTargetPronunciation:
            playTargetPronunciation()
        case let .playName(trackID):
            SoundEffectsController.shared.play(trackID: trackID)
            engine.noteSoundPlayed()
        case .playYay:
            playCorrectSound()
        case let .correctMatch(id):
            applyMatchedAppearance(id: id)
        case let .incorrectMatch(id, _):
            let nameTrackID = engine.letters.first { $0.id == id }?.nameTrackID
            runTapFeedback(
                events: [.incorrectMatch(id: id, pronunciationTrackID: "")],
                nameTrackID: nameTrackID,
                isCorrect: false,
                incorrectID: id
            )
        case .won:
            finishWon()
        }
    }

    /// Tap audio/visual chain (each cue starts when the previous finishes):
    /// switch → tapped letter → correct/error (+ light green / flash red) → next/current target.
    func handleTapEvents(_ events: [GateGraphemeMatchEngineEvent]) {
        let nameTrack = events.compactMap { event -> String? in
            if case let .playName(trackID) = event { return trackID }
            return nil
        }.first
        let isCorrect = events.contains(.playYay)
        let incorrectID = events.compactMap { event -> UUID? in
            if case let .incorrectMatch(id, _) = event { return id }
            return nil
        }.first

        if isCorrect {
            runTapFeedback(events: events, nameTrackID: nameTrack, isCorrect: true)
            return
        }

        if let incorrectID {
            runTapFeedback(
                events: events,
                nameTrackID: nameTrack,
                isCorrect: false,
                incorrectID: incorrectID
            )
            return
        }

        for event in events {
            handle(event)
        }
    }

    func runTapFeedback(
        events: [GateGraphemeMatchEngineEvent],
        nameTrackID: String?,
        isCorrect: Bool,
        incorrectID: UUID? = nil
    ) {
        inputLocked = true

        let matchedID = events.compactMap { event -> UUID? in
            if case let .correctMatch(id) = event { return id }
            return nil
        }.first
        let playTargetPrompt = isCorrect
            ? events.contains(.playTargetPronunciation)
            : true
        let didWin = events.contains(.won)
        let feedbackTrackID = isCorrect ? correctSoundTrackID : errorSoundTrackID
        let feedbackDuration = SoundEffectsController.shared.cueDuration(of: feedbackTrackID)

        var steps: [SKAction] = []
        appendTrackSteps(to: &steps, trackID: nameTrackID)

        // Visual + correct/error only after the letter name cue finishes.
        if isCorrect {
            steps.append(SKAction.run { [weak self] in
                if let matchedID {
                    self?.applyMatchedAppearance(id: matchedID)
                }
                self?.playCorrectSound()
            })
            steps.append(SKAction.wait(forDuration: feedbackDuration))
        } else {
            let flash = wrongFlashAction(for: incorrectID)
            steps.append(SKAction.group([
                flash,
                SKAction.sequence([
                    SKAction.run { [weak self] in self?.playErrorSound() },
                    SKAction.wait(forDuration: feedbackDuration),
                ]),
            ]))
        }

        if playTargetPrompt {
            steps.append(SKAction.run { [weak self] in self?.playTargetPronunciation() })
        }

        steps.append(SKAction.run { [weak self] in
            guard let self else { return }
            if didWin {
                self.finishWon()
            }
            self.inputLocked = false
        })

        run(SKAction.sequence(steps))
    }

    var correctSoundTrackID: String? {
        SoundEffectsController.shared.commonFx.merging(puzzleConfig.fx).trackID(for: "correct")
    }

    var errorSoundTrackID: String? {
        SoundEffectsController.shared.commonFx.merging(puzzleConfig.fx).trackID(for: "error")
    }

    func playCorrectSound() {
        SoundEffectsController.shared.play(
            event: "correct",
            from: SoundEffectsController.shared.commonFx.merging(puzzleConfig.fx)
        )
        engine.noteSoundPlayed()
    }

    func playErrorSound() {
        SoundEffectsController.shared.play(
            event: "error",
            from: SoundEffectsController.shared.commonFx.merging(puzzleConfig.fx)
        )
        engine.noteSoundPlayed()
    }

    func playTargetPronunciation() {
        let trackID = engine.targetPronunciationTrackID
        guard !trackID.isEmpty else { return }
        SoundEffectsController.shared.play(trackID: trackID)
        engine.noteSoundPlayed()
    }

    func appendTrackSteps(to steps: inout [SKAction], trackID: String?) {
        guard let trackID, !trackID.isEmpty else { return }
        let duration = SoundEffectsController.shared.cueDuration(of: trackID)
        steps.append(SKAction.run { [weak self] in
            SoundEffectsController.shared.play(trackID: trackID)
            self?.engine.noteSoundPlayed()
        })
        steps.append(SKAction.wait(forDuration: duration))
    }

    func applyMatchedAppearance(id: UUID) {
        if let switchNode = switchNodes[id], let on = switchTextures?.on {
            let size = switchNode.size
            switchNode.texture = on
            switchNode.size = size
            switchNode.colorBlendFactor = 0
        } else if let square = letterNodes[id]?.childNode(withName: "switchFallback") as? SKShapeNode {
            square.fillColor = squareMatchedFill
        }
        letterNodes[id]?.alpha = 1
    }

    func wrongFlashAction(for id: UUID?) -> SKAction {
        let switchNode = id.flatMap { switchNodes[$0] }
        let fallback = id.flatMap { letterNodes[$0]?.childNode(withName: "switchFallback") as? SKShapeNode }
        return SKAction.doubleFlash(
            apply: { [weak self] in
                if let switchNode {
                    switchNode.color = self?.squareWrongFill ?? .systemRed
                    switchNode.colorBlendFactor = 0.55
                } else {
                    fallback?.fillColor = self?.squareWrongFill ?? .systemRed
                }
            },
            clear: { [weak self] in
                if let switchNode {
                    switchNode.colorBlendFactor = 0
                } else {
                    fallback?.fillColor = self?.squareFill ?? .brown
                }
            }
        )
    }

    func finishWon() {
        guard !didEnd else { return }
        didEnd = true
        isUserInteractionEnabled = false
        SoundEffectsController.shared.playCommon(event: "win")
        if case let .won(stars) = engine.outcome {
            graphemeMatchDelegate?.gateGraphemeMatchSceneDidWin(starsAwarded: stars)
        } else {
            graphemeMatchDelegate?.gateGraphemeMatchSceneDidWin(starsAwarded: engine.letters.count)
        }
    }

    // MARK: - Touch

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !didEnd, !inputLocked, let touch = touches.first else { return }
        let location = touch.location(in: self)

        guard let id = letterID(at: location),
              !engine.matchedIDs.contains(id) else { return }

        // switch → tapped letter → correct/error → next/current target (see handleTapEvents).
        SoundEffectsController.shared.play(event: "switch_push", from: puzzleConfig.fx)
        engine.noteSoundPlayed()
        let events = engine.tapLetter(id: id)
        guard !events.isEmpty else { return }
        let pushDuration = SoundEffectsController.shared.cueDuration(
            of: puzzleConfig.fx.trackID(for: "switch_push")
        )
        inputLocked = true
        run(SKAction.sequence([
            SKAction.wait(forDuration: pushDuration),
            SKAction.run { [weak self] in
                self?.handleTapEvents(events)
            },
        ]))
    }

    func letterID(at point: CGPoint) -> UUID? {
        let side = laidOutTileSide > 0 ? laidOutTileSide : preferredTileSize
        for (id, node) in letterNodes {
            let half = side * 0.5
            let bounds = CGRect(
                x: node.position.x - half,
                y: node.position.y - half,
                width: side,
                height: side
            )
            if bounds.contains(point) {
                return id
            }
        }
        return nil
    }
}
