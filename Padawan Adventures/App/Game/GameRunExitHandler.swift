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

    /// Persists vitals / completion / mid-run save for a run exit. Separated for unit tests.
    static func persistExitState(
        completedLevel: Bool,
        world: GameWorld?,
        session: AppSession
    ) async {
        if let world {
            await session.syncVitals(from: world)
        }

        if completedLevel {
            // Completion must not depend on a live world snapshot — the scene can be gone by exit.
            if let resourceName = session.selectedLevelResourceName {
                await session.markLevelCompleted(resourceName: resourceName)
            }
            try? await session.saveService.delete()
        } else if let world {
            try? await session.saveService.save(world)
        }

        await session.refreshContinueEligibility()
    }

    func exitToLevelSelect(
        completedLevel: Bool,
        gameScene: GameScene?,
        session: AppSession,
        hostWindow: UIWindow?
    ) {
        guard !isExitingToLevelSelect else { return }
        isExitingToLevelSelect = true

        Task {
            await Self.persistExitState(
                completedLevel: completedLevel,
                world: gameScene?.currentWorld,
                session: session
            )
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
