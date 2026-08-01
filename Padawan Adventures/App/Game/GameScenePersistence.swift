//
//  GameScenePersistence.swift
//  Padawan Adventures
//

import SpriteKit

extension GameScene {
    func captureContinueAndSave() {
        continuePoint.capture(world)
        scheduleSave()
    }

    func scheduleSave() {
        let snapshot = world
        onWorldSaved?(snapshot)
        guard let saveService else { return }
        Task {
            try? await saveService.save(snapshot)
        }
    }
}
