import SpriteKit
import UIKit

extension GateScene {
    func playWordSound() {
        removeAction(forKey: Self.connectedSoundActionKey)
        let trackID = engine.targetSoundTrackID
        guard !trackID.isEmpty else { return }
        SoundEffectsController.shared.play(trackID: trackID)
    }

    /// Progressive cue for a newly lengthened connected prefix (no full-word spelling replay).
    func playConnectedPrefixSound(_ prefix: String) {
        removeAction(forKey: Self.connectedSoundActionKey)
        guard !prefix.isEmpty,
              let progressiveID = engine.targetEntry.progressiveTrack(forPrefix: prefix),
              !progressiveID.isEmpty else {
            return
        }
        SoundEffectsController.shared.play(trackID: progressiveID)
    }

    func beginWinSequence() {
        guard !didEnd, !isCompletingWin else { return }
        isCompletingWin = true
        isUserInteractionEnabled = false
        draggedNode = nil
        // Draw the final right-end connector before win SFX / overlay.
        updateCorrectOrderConnectors()
        removeAction(forKey: Self.winSequenceActionKey)
        run(
            SKAction.sequence([
                SKAction.wait(forDuration: Self.winConnectorHoldDuration),
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
        SoundEffectsController.shared.play(
            event: "win",
            from: SoundEffectsController.shared.commonFx.merging(puzzleConfig.fx)
        )
        if case let .won(stars) = engine.outcome {
            gateDelegate?.gateSceneDidWin(starsAwarded: stars)
        } else {
            gateDelegate?.gateSceneDidWin(starsAwarded: engine.targetWord.count)
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
