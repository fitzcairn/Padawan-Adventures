import SpriteKit

extension GateSoundOutWordScene {
    var mergedFx: SoundEffectTable {
        SoundEffectsController.shared.commonFx.merging(puzzleConfig.fx)
    }

    var correctSoundTrackID: String? { mergedFx.trackID(for: "correct") }
    var errorSoundTrackID: String? { mergedFx.trackID(for: "error") }

    /// Full word — the opening cue, picture taps, and the read-back after the last grapheme.
    func playWordSound() {
        let trackID = engine.wordTrackID
        guard !trackID.isEmpty else { return }
        SoundEffectsController.shared.play(trackID: trackID)
    }

    /// Letter name ("bee") for the flashing prompt and for taps on the word text.
    func playGraphemeName(_ grapheme: String) {
        guard let trackID = engine.nameTrackID(for: grapheme) else { return }
        SoundEffectsController.shared.play(trackID: trackID)
    }

    func playPromptLetterName(at index: Int) {
        guard let grapheme = engine.grapheme(at: index) else { return }
        playGraphemeName(grapheme)
    }

    /// Letter sound ("buh") for the grapheme hidden behind a blank capacitor.
    func playChoiceSound(choiceID: UUID) {
        guard let choice = engine.currentChoices.first(where: { $0.id == choiceID }),
              let trackID = engine.soundTrackID(for: choice.grapheme) else {
            return
        }
        SoundEffectsController.shared.play(trackID: trackID)
    }

    func playCorrectSound() {
        SoundEffectsController.shared.play(event: "correct", from: mergedFx)
    }

    func playErrorSound() {
        SoundEffectsController.shared.play(event: "error", from: mergedFx)
    }

    /// Holds the finished circuit, reads the whole word back, then hands off the win.
    func beginWinSequence() {
        guard !didEnd, !isCompletingWin else { return }
        isCompletingWin = true
        inputLocked = true
        dragChoiceID = nil
        clearChoiceNodes()
        updateConnectors()

        let wordDuration = SoundEffectsController.shared.cueDuration(of: engine.wordTrackID)
        removeAction(forKey: Self.winSequenceActionKey)
        run(
            SKAction.sequence([
                SKAction.wait(forDuration: Self.winConnectorHoldDuration),
                SKAction.run { [weak self] in self?.playWordSound() },
                SKAction.wait(forDuration: wordDuration),
                SKAction.run { [weak self] in self?.finishWon() },
            ]),
            withKey: Self.winSequenceActionKey
        )
    }

    func finishWon() {
        guard !didEnd else { return }
        didEnd = true
        isUserInteractionEnabled = false
        stopGateLoop()
        SoundEffectsController.shared.play(event: "win", from: mergedFx)
        if case let .won(stars) = engine.outcome {
            soundOutWordDelegate?.gateSoundOutWordSceneDidWin(starsAwarded: stars)
        } else {
            soundOutWordDelegate?.gateSoundOutWordSceneDidWin(
                starsAwarded: engine.targetGraphemes.count
            )
        }
    }

    func stopGateLoop() {
        SoundEffectsController.shared.stopLoop(trackID: activeLoopTrackID)
        activeLoopTrackID = nil
    }

    /// Arc loop plays only while electricity connectors are visible.
    func syncArcLoopWithConnectors() {
        if connectorSegments.isEmpty {
            stopGateLoop()
            return
        }
        guard activeLoopTrackID == nil else { return }
        activeLoopTrackID = SoundEffectsController.shared.startLoop(
            event: "loop",
            from: puzzleConfig.fx
        )
    }
}
