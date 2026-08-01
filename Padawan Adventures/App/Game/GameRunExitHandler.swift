//
//  GameRunExitHandler.swift
//  Padawan Adventures
//

import UIKit
import SwiftUI

/// Handles level-run exit: vitals sync, save/continue, asset release, navigation to level select.
@MainActor
final class GameRunExitHandler {
    private var isExitingToLevelSelect = false

    func exitToLevelSelect(
        completedLevel: Bool,
        gameScene: GameScene?,
        session: AppSession,
        hostWindow: UIWindow?
    ) {
        guard !isExitingToLevelSelect else { return }
        isExitingToLevelSelect = true

        Task {
            if let snapshot = gameScene?.currentWorld {
                await session.syncVitals(from: snapshot)
                if completedLevel {
                    if let resourceName = session.selectedLevelResourceName {
                        await session.markLevelCompleted(resourceName: resourceName)
                    }
                    try? await session.saveService.delete()
                } else {
                    try? await session.saveService.save(snapshot)
                }
            }
            await session.refreshContinueEligibility()
            session.releaseLevelScopedAssets()
            session.startObservingMemoryPressure()

            let flow = LandscapeSwiftUIHost(
                rootView: FlowRootView(
                    session: session,
                    router: .postGameRouter()
                )
            )

            AppWindow.setRoot(flow, in: hostWindow ?? AppWindow.key)
        }
    }
}
