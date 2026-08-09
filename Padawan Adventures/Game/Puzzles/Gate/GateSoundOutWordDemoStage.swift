import SpriteKit

extension GateSoundOutWordScene: MinigameDemoStage {
    var demoAcceptsInput: Bool {
        !didEnd
            && !inputLocked
            && !isCompletingWin
            && dragChoiceID == nil
            && !choiceNodes.isEmpty
    }

    var demoMoves: [MinigameDemoMove] {
        // Prefer the leftmost legal slot so placed capacitors sit left-to-right and
        // the electricity arcs chain cleanly (endpoint → letter → letter → …).
        guard let index = engine.currentIndex else { return [] }
        let ideal = CGPoint(x: minDropX(forIndex: index), y: playAreaRect.midY)
        let drop = nearestValidDropPoint(to: ideal) ?? ideal
        guard isValidDrop(drop) else { return [] }
        let answer = engine.currentGrapheme
        return engine.currentChoices.compactMap { choice in
            guard let node = choiceNodes[choice.id] else { return nil }
            return MinigameDemoMove(
                gesture: .drag(from: node.position, to: drop),
                isCorrect: choice.grapheme == answer,
                coinAnchor: drop
            )
        }
    }

    var demoCoinAnchor: CGPoint? { placedNodes.last?.position }

    var demoIsFinished: Bool { didEnd || isCompletingWin }

    var demoScript: MinigameDemoScript? { GateSoundOutWordDemoScript(stage: self) }

    /// Replays the opening word cue suppressed during the tutorial lead-in.
    func demoResumeGameplayAudio() {
        playWordSound()
        syncArcLoopWithConnectors()
    }
}

extension GateSoundOutWordScene: GateSoundOutWordDemoStaging {
    var demoIsReady: Bool { demoAcceptsInput }
    var demoIsOver: Bool { demoIsFinished }

    /// Centre of the prompt's picture region in scene coordinates; nil when there is no
    /// illustration (word-only plate).
    var demoPictureTap: CGPoint? {
        guard let prompt, promptImage != nil else { return nil }
        let local = CGPoint(
            x: prompt.regions.pictureRect.midX,
            y: prompt.regions.pictureRect.midY
        )
        return prompt.plate.convert(local, to: self)
    }

    /// Centre of the prompt's word band in scene coordinates.
    var demoWordPlateTap: CGPoint? {
        guard let prompt else { return nil }
        let local = CGPoint(
            x: prompt.regions.wordBandRect.midX,
            y: prompt.regions.wordBandRect.midY
        )
        return prompt.plate.convert(local, to: self)
    }

    /// Ordered by the engine's set, not by `choiceNodes` (a dictionary), so the demo
    /// taps left to right and keeps doing so after a reshuffle.
    var demoChoiceTaps: [GateSoundOutWordDemoCue] {
        engine.currentChoices.compactMap { choice in
            guard let node = choiceNodes[choice.id] else { return nil }
            return GateSoundOutWordDemoCue(
                point: node.position,
                seconds: SoundEffectsController.shared.cueDuration(
                    of: engine.soundTrackID(for: choice.grapheme)
                )
            )
        }
    }

    var demoWordCueSeconds: TimeInterval {
        SoundEffectsController.shared.cueDuration(of: engine.wordTrackID)
    }

    var demoLetterNameCueSeconds: TimeInterval {
        SoundEffectsController.shared.cueDuration(
            of: engine.currentGrapheme.flatMap { engine.nameTrackID(for: $0) }
        )
    }

    var demoWrongMove: MinigameDemoMove? { demoMoves.first { !$0.isCorrect } }
    var demoCorrectMove: MinigameDemoMove? { demoMoves.first { $0.isCorrect } }
    var demoIsWordSolved: Bool { engine.isSolved }

    func demoRestart() {
        removeAction(forKey: Self.winSequenceActionKey)
        removeAction(forKey: Self.promptActionKey)
        removeAction(forKey: Self.feedbackActionKey)
        stopGateLoop()
        didEnd = false
        isCompletingWin = false
        inputLocked = false
        dragChoiceID = nil
        dragMoved = false
        isUserInteractionEnabled = true
        // `buildPuzzle()` clears the node arrays but not the resize bookkeeping.
        placedFractions = []
        preservingDemoOverlays {
            engine.begin()
            buildPuzzle()
        }
        beginRound()
    }
}
