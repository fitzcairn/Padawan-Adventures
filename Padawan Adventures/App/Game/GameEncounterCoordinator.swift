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
        @ViewBuilder makeView: @escaping (_ finish: @escaping (MinigameOutcome) -> Void) -> Content,
        onOutcome: @escaping (_ outcome: MinigameOutcome?, _ done: @escaping () -> Void) -> Void
    ) {
        BackgroundMusicController.shared.apply(music)
        MemoryProbe.mark("minigame-present-\(memoryLabel)")

        let outcomeBox = MinigameOutcomeBox()

        overlayPresenter.present(
            fadeWorldOut: true,
            makeViewController: {
                self.buildOverlayHost { overlayFinish in
                    AnyView(makeView { outcome in
                        outcomeBox.outcome = outcome
                        overlayFinish()
                    })
                }
            },
            onResolved: { done in
                MemoryProbe.mark("minigame-dismiss-\(memoryLabel)")
                onOutcome(outcomeBox.outcome, done)
            }
        )
    }
}

/// Captures minigame result across the overlay finish callback.
private final class MinigameOutcomeBox {
    var outcome: MinigameOutcome?
}
