import SpriteKit

extension GateWordPlugScene {
    // MARK: - Touch

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !didEnd, !inputLocked, let touch = touches.first else { return }
        let p = touch.location(in: self)
        if let id = draggableToken(at: p), let node = tokenNodes[id] {
            dragTokenID = id
            dragStart = p
            dragMoved = false
            dragOffset = CGPoint(x: node.position.x - p.x, y: node.position.y - p.y)
            node.zPosition = 100
            return
        }
        if let slotID = plateSlot(at: p) {
            handle(engine.tapWord(slotID: slotID))
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !didEnd, !inputLocked, let dragTokenID, let touch = touches.first,
              let node = tokenNodes[dragTokenID] else { return }
        let p = touch.location(in: self)
        if hypot(p.x - dragStart.x, p.y - dragStart.y) > tapMoveThreshold {
            dragMoved = true
        }
        node.position = CGPoint(x: p.x + dragOffset.x, y: p.y + dragOffset.y)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        endDrag()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let id = dragTokenID else { return }
        animateTokenHome(id: id)
        tokenNodes[id]?.zPosition = 20
        dragTokenID = nil
        dragMoved = false
    }

    func endDrag() {
        guard let id = dragTokenID, let node = tokenNodes[id] else { return }
        defer {
            dragTokenID = nil
            dragMoved = false
            node.zPosition = 20
        }

        if let slotID = emptySocket(containing: node.position) {
            let events = engine.plug(letterID: id, intoSlotID: slotID)
            guard !events.isEmpty else {
                animateTokenHome(id: id)
                return
            }
            handlePlugEvents(events, letterID: id, slotID: slotID)
            return
        }

        if !dragMoved {
            handle(engine.tapLetter(id: id))
        }
        animateTokenHome(id: id)
    }

    // MARK: - Events / feedback

    func handle(_ events: [GateWordPlugEngineEvent]) {
        guard !events.isEmpty else { return }

        if events.contains(where: {
            if case .playLetterName = $0 { return true }
            return false
        }) {
            runLetterTapFeedback(events)
            return
        }

        if case let .playWordSound(trackID) = events.first {
            inputLocked = true
            var steps: [SKAction] = []
            appendTrackSteps(to: &steps, trackID: trackID)
            steps.append(SKAction.run { [weak self] in self?.inputLocked = false })
            run(SKAction.sequence(steps))
            return
        }

        for event in events {
            handleSingle(event)
        }
    }

    func handleSingle(_ event: GateWordPlugEngineEvent) {
        switch event {
        case let .playWordSound(trackID):
            SoundEffectsController.shared.play(trackID: trackID)
        case let .playLetterName(trackID), let .playLetterSound(trackID):
            SoundEffectsController.shared.play(trackID: trackID)
        case .playCorrect:
            playCorrectSound()
        case let .speakPhrase(text):
            SpokenPhrasePlayer.shared.speak(text)
        case let .correctPlug(slotID, letterID):
            applySolvedAppearance(slotID: slotID)
            if let socket = socketNodes[slotID], let token = tokenNodes[letterID] {
                token.position = socket.position
            }
        case let .incorrectPlug(letterID):
            animateTokenHome(id: letterID)
        case .won:
            finishWon()
        }
    }

    func runLetterTapFeedback(_ events: [GateWordPlugEngineEvent]) {
        inputLocked = true
        var steps: [SKAction] = []
        for event in events {
            switch event {
            case let .playLetterName(trackID), let .playLetterSound(trackID):
                appendTrackSteps(to: &steps, trackID: trackID)
            default:
                break
            }
        }
        steps.append(SKAction.run { [weak self] in self?.inputLocked = false })
        run(SKAction.sequence(steps))
    }

    func handlePlugEvents(
        _ events: [GateWordPlugEngineEvent],
        letterID: UUID,
        slotID: UUID
    ) {
        let isCorrect = events.contains {
            if case .correctPlug = $0 { return true }
            return false
        }
        let didWin = events.contains(.won)
        let phrase = events.compactMap { event -> String? in
            if case let .speakPhrase(text) = event { return text }
            return nil
        }.first

        inputLocked = true

        if isCorrect {
            if let socket = socketNodes[slotID], let token = tokenNodes[letterID] {
                token.position = socket.position
            }
            let flash = SKAction.doubleFlash(
                period: 0.18,
                count: 2,
                apply: { [weak self] in
                    self?.plateNodes[slotID]?.fillColor = self?.solvedFill ?? .green
                    self?.socketNodes[slotID]?.fillColor = self?.solvedFill ?? .green
                },
                clear: { [weak self] in
                    self?.plateNodes[slotID]?.fillColor = self?.rectFill ?? .blue
                    self?.socketNodes[slotID]?.fillColor = self?.socketFill ?? .gray
                }
            )
            let feedbackDuration = SoundEffectsController.shared.cueDuration(of: correctSoundTrackID)
            var audioSteps: [SKAction] = [
                SKAction.run { [weak self] in self?.playCorrectSound() },
                SKAction.wait(forDuration: feedbackDuration),
            ]
            if let phrase {
                audioSteps.append(SKAction.run { [weak self] in
                    self?.speak(phrase) {
                        guard let self else { return }
                        self.applySolvedAppearance(slotID: slotID)
                        if didWin {
                            self.finishWon()
                        } else {
                            self.inputLocked = false
                        }
                    }
                })
            } else {
                audioSteps.append(SKAction.run { [weak self] in
                    guard let self else { return }
                    self.applySolvedAppearance(slotID: slotID)
                    if didWin {
                        self.finishWon()
                    } else {
                        self.inputLocked = false
                    }
                })
            }
            run(SKAction.group([
                flash,
                SKAction.sequence(audioSteps),
            ]))
            return
        }

        let flash = SKAction.doubleFlash(
            period: 0.12,
            count: 2,
            apply: { [weak self] in
                self?.tokenCircles[letterID]?.fillColor = self?.wrongFill ?? .red
            },
            clear: { [weak self] in
                self?.tokenCircles[letterID]?.fillColor = self?.tokenFill ?? .darkGray
            }
        )
        let feedbackDuration = SoundEffectsController.shared.cueDuration(of: errorSoundTrackID)
        run(SKAction.sequence([
            SKAction.group([
                flash,
                SKAction.sequence([
                    SKAction.run { [weak self] in self?.playErrorSound() },
                    SKAction.wait(forDuration: feedbackDuration),
                ]),
            ]),
            SKAction.run { [weak self] in
                self?.animateTokenHome(id: letterID)
                self?.inputLocked = false
            },
        ]))
    }

    func applySolvedAppearance(slotID: UUID) {
        plateNodes[slotID]?.fillColor = solvedFill
        socketNodes[slotID]?.fillColor = solvedFill
    }

    func animateTokenHome(id: UUID) {
        guard let node = tokenNodes[id], let home = tokenHome[id] else { return }
        node.run(SKAction.move(to: home, duration: 0.15).withTimingMode(.easeOut))
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
    }

    func playErrorSound() {
        SoundEffectsController.shared.play(
            event: "error",
            from: SoundEffectsController.shared.commonFx.merging(puzzleConfig.fx)
        )
    }

    func appendTrackSteps(to steps: inout [SKAction], trackID: String?) {
        guard let trackID, !trackID.isEmpty else { return }
        let duration = SoundEffectsController.shared.cueDuration(of: trackID)
        steps.append(SKAction.run {
            SoundEffectsController.shared.play(trackID: trackID)
        })
        steps.append(SKAction.wait(forDuration: duration))
    }

    func speak(_ text: String, then next: @escaping () -> Void) {
        var resumed = false
        let resume = {
            if !resumed {
                resumed = true
                next()
            }
        }
        SpokenPhrasePlayer.shared.speak(text) { resume() }
        run(.sequence([.wait(forDuration: 6), .run { resume() }]))
    }

    func finishWon() {
        guard !didEnd else { return }
        didEnd = true
        isUserInteractionEnabled = false
        SoundEffectsController.shared.playCommon(event: "win")
        if case let .won(stars) = engine.outcome {
            wordPlugDelegate?.gateWordPlugSceneDidWin(starsAwarded: stars)
        } else {
            wordPlugDelegate?.gateWordPlugSceneDidWin(starsAwarded: engine.slots.count)
        }
    }
}
