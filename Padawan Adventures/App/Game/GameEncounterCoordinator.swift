//
//  GameEncounterCoordinator.swift
//  Padawan Adventures
//

import SwiftUI

/// Shared minigame presentation: music swap, overlay present/dismiss, outcome capture.
@MainActor
final class GameEncounterCoordinator {
    private let overlayPresenter: FullscreenOverlayPresenter
    private let buildOverlayHost: (@escaping (@escaping () -> Void) -> AnyView) -> FullscreenOverlayHost

    init(
        overlayPresenter: FullscreenOverlayPresenter,
        buildOverlayHost: @escaping (@escaping (@escaping () -> Void) -> AnyView) -> FullscreenOverlayHost
    ) {
        self.overlayPresenter = overlayPresenter
        self.buildOverlayHost = buildOverlayHost
    }

    func presentMinigame<Content: View>(
        music: MusicCue,
        memoryLabel: String,
        showInstructions: Bool,
        instructionsKey: String,
        onInstructionsAcknowledged: @escaping () -> Void,
        @ViewBuilder makeView: @escaping (_ finish: @escaping (MinigameOutcome) -> Void) -> Content,
        onOutcome: @escaping (_ outcome: MinigameOutcome?, _ returnToWorld: OverlayReturn) -> Void
    ) {
        // World one-shots (notice, footsteps, etc.) can still be audible when the
        // overlay starts — clear them so minigame / combat audio owns the mix.
        SoundEffectsController.shared.fadeOutAndStopAll()
        BackgroundMusicController.shared.apply(music)
        MemoryProbe.mark("minigame-present-\(memoryLabel)")

        let outcomeBox = MinigameOutcomeBox()

        overlayPresenter.present(
            fadeWorldOut: true,
            makeViewController: {
                self.buildOverlayHost { overlayFinish in
                    AnyView(
                        MinigameInstructionsGate(
                            needsInstructions: showInstructions,
                            instructionsKey: instructionsKey,
                            onAcknowledged: onInstructionsAcknowledged
                        ) {
                            makeView { outcome in
                                outcomeBox.outcome = outcome
                                overlayFinish()
                            }
                        }
                    )
                }
            },
            onResolved: { returnToWorld in
                MemoryProbe.mark("minigame-dismiss-\(memoryLabel)")
                onOutcome(outcomeBox.outcome, returnToWorld)
            }
        )
    }
}

/// Captures minigame result across the overlay finish callback.
private final class MinigameOutcomeBox {
    var outcome: MinigameOutcome?
}
