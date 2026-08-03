//
//  GameSceneEncounterResolver.swift
//  Padawan Adventures
//

import SpriteKit

extension GameScene {
    /// Removes the enemy after a fight, fades the world back in with the sprite
    /// still visible, then plays the red-sparkle defeat fade before resuming.
    func resolveEnemyEncounter(enemyID: UUID, completion: (() -> Void)? = nil) {
        simulationLoop.removeEnemy(id: enemyID, from: &world)
        pendingInput = PendingInput()
        // Detach before sync so the sprite stays on screen for the defeat fade.
        let defeatNode = renderer.detachEntityNode(id: enemyID)
        renderer.syncEntities(world.entities)
        resumeWorldPlayerIdle()
        captureContinueAndSave()
        renderer.fadeWorldIn { [weak self] in
            guard let self else { return }
            guard let defeatNode else {
                self.isPausedForEncounter = false
                completion?()
                return
            }
            PlaceholderFactory.playDefeatAnimation(on: defeatNode) {
                defeatNode.removeFromParent()
                self.isPausedForEncounter = false
                completion?()
            }
        }
    }

    /// Fills the pit blob into ordinary floor after a successful escape, then resumes.
    func resolvePitWin(completion: (() -> Void)? = nil) {
        if let pit = world.playerPosition {
            _ = world.fillPit(at: pit)
        }
        pendingInput = PendingInput()
        renderer.render(world: world, focus: viewportFocus)
        showFixedZoomView()
        resumeWorldPlayerIdle()
        captureContinueAndSave()
        renderer.fadeWorldIn { [weak self] in
            self?.isPausedForEncounter = false
            completion?()
        }
    }

    /// Retreats the player to the approach tile after a pit timeout (pit stays).
    func resolvePitTimeout(approach: GridCoord, completion: (() -> Void)? = nil) {
        world.setPlayerPosition(approach)
        pendingInput = PendingInput()
        renderer.syncEntities(world.entities)
        renderer.render(world: world, focus: viewportFocus)
        showFixedZoomView()
        resumeWorldPlayerIdle()
        // Do not overwrite Continue — the last safe world remains before the failed attempt.
        renderer.fadeWorldIn { [weak self] in
            self?.isPausedForEncounter = false
            completion?()
        }
    }

    /// Opens a beaten gate: fade the world back in, then dissolve the gate with sparkles
    /// while the two connecting floor tiles and the room it was sealing fade in
    /// (`gateOpenDuration`).
    func resolveGateEncounter(at coord: GridCoord, completion: (() -> Void)? = nil) {
        pendingInput = PendingInput()
        // Keep the gate sprite around for the dissolve; openGate converts cells to floor.
        let gateNode = renderer.detachGateNode(at: coord, in: world)
        let openedCoords = world.openGate(at: coord)
        renderer.armRevealFade()
        renderer.render(world: world, focus: viewportFocus)
        renderer.setFloorNodesAlpha(0, at: openedCoords)
        resumeWorldPlayerIdle()
        captureContinueAndSave()
        renderer.fadeWorldIn { [weak self] in
            guard let self else { return }
            if !openedCoords.isEmpty {
                SoundEffectsController.shared.play(event: "gate_opened", from: self.worldFx)
            }
            self.renderer.playGateOpenAnimation(
                gateNode: gateNode,
                floorCoords: openedCoords
            ) {
                self.isPausedForEncounter = false
                completion?()
            }
        }
    }

    /// Retreats the player off the gate after a timeout (gate stays closed).
    func resolveGateTimeout(approach: GridCoord, completion: (() -> Void)? = nil) {
        world.setPlayerPosition(approach)
        pendingInput = PendingInput()
        renderer.syncEntities(world.entities)
        renderer.render(world: world, focus: viewportFocus)
        resumeWorldPlayerIdle()
        // Do not overwrite Continue — the last safe world remains before the failed attempt.
        renderer.fadeWorldIn { [weak self] in
            self?.isPausedForEncounter = false
            completion?()
        }
    }

    /// Deducts one energy (no-op at 0). Returns the new energy count.
    /// Does not persist — Continue stays on the last safe world until the encounter resolves.
    @discardableResult
    func deductEnergy() -> Int {
        world.energyCount = max(0, world.energyCount - 1)
        return world.energyCount
    }

    /// Deducts one health (no-op at 0). Returns the new health count.
    /// Does not persist — Continue stays on the last safe world until the encounter resolves.
    @discardableResult
    func deductHealth() -> Int {
        world.healthCount = max(0, world.healthCount - 1)
        return world.healthCount
    }

    /// Restores the world to the last safe continue snapshot and resumes play.
    func restoreFromContinuePoint(completion: (() -> Void)? = nil) {
        world = continuePoint.snapshot
        world.healthCount = DefeatRules.restoredVital(world.healthCount)
        world.energyCount = DefeatRules.restoredVital(world.energyCount)
        world.separateNearbyEnemiesOnRestore()
        movement = MovementSystem()
        pendingInput = PendingInput()
        simulationLoop = SimulationLoop(isoConfig: isoConfig, enemyConfig: enemyConfig)
        showFixedZoomView()
        resumeWorldPlayerIdle()
        onVitalsRestored?(world.healthCount, world.energyCount)
        captureContinueAndSave()
        renderer.fadeWorldIn { [weak self] in
            self?.isPausedForEncounter = false
            completion?()
        }
    }
}
