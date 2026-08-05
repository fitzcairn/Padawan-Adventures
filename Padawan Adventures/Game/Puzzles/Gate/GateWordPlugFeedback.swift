import SpriteKit

extension GateWordPlugScene {
    // MARK: - Touch

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !didEnd, let touch = touches.first else { return }
        let p = touch.location(in: self)
        // Plugs stay draggable during feedback lock; only non-drag taps wait.
        if let id = draggableToken(at: p), let node = tokenNodes[id] {
            dragTokenID = id
            dragStart = p
            dragMoved = false
            dragOffset = CGPoint(x: node.position.x - p.x, y: node.position.y - p.y)
            node.zPosition = 100
            beginDragCable(for: id)
            // Pronunciation plays on touch-down (tap or drag start), not on release.
            handle(engine.tapLetter(id: id))
            return
        }
        guard !inputLocked else { return }
        if let slotID = plateSlot(at: p) {
            handle(engine.tapWord(slotID: slotID))
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !didEnd, let dragTokenID, let touch = touches.first,
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
        tearDownCable(for: id)
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
                tearDownCable(for: id)
                animateTokenHome(id: id)
                return
            }
            let isCorrect = events.contains {
                if case .correctPlug = $0 { return true }
                return false
            }
            if isCorrect {
                // Keep tether and show power flowing through the cable.
                energizeCable(for: id)
            } else {
                tearDownCable(for: id)
            }
            handlePlugEvents(events, letterID: id, slotID: slotID)
            return
        }

        tearDownCable(for: id)
        if !dragMoved {
            return
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

        inputLocked = true

        if isCorrect {
            if let socket = socketNodes[slotID], let token = tokenNodes[letterID] {
                token.position = socket.position
            }
            let flash = SKAction.doubleFlash(
                period: 0.18,
                count: 2,
                apply: { [weak self] in
                    guard let self else { return }
                    self.plateNodes[slotID]?.color = self.solvedFill
                    self.plateNodes[slotID]?.colorBlendFactor = 0.55
                    self.socketNodes[slotID]?.color = self.solvedFill
                    self.socketNodes[slotID]?.colorBlendFactor = 0.45
                },
                clear: { [weak self] in
                    self?.plateNodes[slotID]?.colorBlendFactor = 0
                    self?.socketNodes[slotID]?.colorBlendFactor = 0
                }
            )
            let wordTrackID = events.compactMap { event -> String? in
                if case let .playWordSound(trackID) = event { return trackID }
                return nil
            }.first
            let chimeDuration = SoundEffectsController.shared.cueDuration(of: correctSoundTrackID)
            var audioSteps: [SKAction] = []
            appendTrackSteps(to: &audioSteps, trackID: wordTrackID)
            audioSteps.append(contentsOf: [
                SKAction.run { [weak self] in self?.playCorrectSound() },
                SKAction.wait(forDuration: chimeDuration),
                SKAction.run { [weak self] in
                    guard let self else { return }
                    self.applySolvedAppearance(slotID: slotID)
                    if didWin {
                        self.finishWon()
                    } else {
                        self.inputLocked = false
                    }
                },
            ])
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
                self?.tokenPlugs[letterID]?.color = self?.wrongFill ?? .red
                self?.tokenPlugs[letterID]?.colorBlendFactor = 0.55
            },
            clear: { [weak self] in
                self?.tokenPlugs[letterID]?.colorBlendFactor = 0
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
        if let plate = plateNodes[slotID], let slot = engine.slot(id: slotID) {
            plate.texture = StarWarsConsoleView.makeTexture(
                text: slot.word,
                size: plate.size,
                isSolved: true
            )
            plate.colorBlendFactor = 0
        }
        if let socket = socketNodes[slotID] {
            socket.color = solvedFill
            socket.colorBlendFactor = 0.35
        }
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

    func finishWon() {
        guard !didEnd else { return }
        didEnd = true
        isUserInteractionEnabled = false
        stopArcLoop()
        SoundEffectsController.shared.playCommon(event: "win")
        if case let .won(stars) = engine.outcome {
            wordPlugDelegate?.gateWordPlugSceneDidWin(starsAwarded: stars)
        } else {
            wordPlugDelegate?.gateWordPlugSceneDidWin(starsAwarded: engine.slots.count)
        }
    }

    /// Arc loop plays quietly while any correct plug remains connected.
    func syncArcLoop() {
        if didEnd || engine.plugged.isEmpty {
            stopArcLoop()
            return
        }
        guard activeLoopTrackID == nil else { return }
        if let trackID = SoundEffectsController.shared.startLoop(
            event: "loop",
            from: puzzleConfig.fx,
            volumeScale: Self.arcLoopQuietScale
        ) {
            activeLoopTrackID = trackID
            return
        }
        SoundEffectsController.shared.startLoop(
            trackID: Self.arcLoopFallbackTrackID,
            volumeScale: Self.arcLoopQuietScale
        )
        activeLoopTrackID = Self.arcLoopFallbackTrackID
    }

    func stopArcLoop() {
        SoundEffectsController.shared.stopLoop(trackID: activeLoopTrackID)
        activeLoopTrackID = nil
    }
}
