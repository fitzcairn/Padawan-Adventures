//
//  GameSceneEncounterResolver.swift
//  Padawan Adventures
//

import SpriteKit

extension GameScene {
    // MARK: - Enemy

    /// Removes the enemy after a fight and keeps the sprite for the defeat fade.
    /// World stays covered / faded; call reveal after returning to the world.
    @discardableResult
    func prepareEnemyEncounterWin(enemyID: UUID) -> SKNode? {
        simulationLoop.removeEnemy(id: enemyID, from: &world)
        pendingInput = PendingInput()
        // Detach before sync so the sprite stays on screen for the defeat fade.
        let defeatNode = renderer.detachEntityNode(id: enemyID)
        renderer.syncEntities(world.entities)
        resumeWorldPlayerIdle()
        captureContinueAndSave()
        return defeatNode
    }

    /// Plays the red-sparkle defeat fade after the world is visible again.
    func revealEnemyEncounterWin(defeatNode: SKNode?, completion: (() -> Void)? = nil) {
        guard let defeatNode else {
            isPausedForEncounter = false
            completion?()
            return
        }
        PlaceholderFactory.playDefeatAnimation(on: defeatNode) {
            defeatNode.removeFromParent()
            self.isPausedForEncounter = false
            completion?()
        }
    }

    /// Removes the enemy after a fight, fades the world back in with the sprite
    /// still visible, then plays the red-sparkle defeat fade before resuming.
    func resolveEnemyEncounter(enemyID: UUID, completion: (() -> Void)? = nil) {
        let defeatNode = prepareEnemyEncounterWin(enemyID: enemyID)
        fadeSimulationIn { [weak self] in
            self?.revealEnemyEncounterWin(defeatNode: defeatNode, completion: completion)
        }
    }

    // MARK: - Pit

    /// Fills the pit blob into ordinary floor after a successful escape.
    func preparePitWin() {
        if let pit = world.playerPosition {
            _ = world.fillPit(at: pit)
        }
        pendingInput = PendingInput()
        renderer.render(world: world, focus: viewportFocus)
        showFixedZoomView()
        resumeWorldPlayerIdle()
        captureContinueAndSave()
    }

    func revealPitWin(completion: (() -> Void)? = nil) {
        isPausedForEncounter = false
        completion?()
    }

    /// Fills the pit blob into ordinary floor after a successful escape, then resumes.
    func resolvePitWin(completion: (() -> Void)? = nil) {
        preparePitWin()
        fadeSimulationIn { [weak self] in
            self?.revealPitWin(completion: completion)
        }
    }

    /// Retreats the player to the approach tile after a pit timeout (pit stays).
    func preparePitTimeout(approach: GridCoord) {
        world.setPlayerPosition(approach)
        pendingInput = PendingInput()
        renderer.syncEntities(world.entities)
        renderer.render(world: world, focus: viewportFocus)
        showFixedZoomView()
        resumeWorldPlayerIdle()
        // Do not overwrite Continue — the last safe world remains before the failed attempt.
    }

    func revealPitTimeout(completion: (() -> Void)? = nil) {
        isPausedForEncounter = false
        completion?()
    }

    /// Retreats the player to the approach tile after a pit timeout (pit stays).
    func resolvePitTimeout(approach: GridCoord, completion: (() -> Void)? = nil) {
        preparePitTimeout(approach: approach)
        fadeSimulationIn { [weak self] in
            self?.revealPitTimeout(completion: completion)
        }
    }

    // MARK: - Gate

    /// Opens a beaten gate under cover. Returns nodes needed for the post-reveal dissolve.
    func prepareGateEncounter(at coord: GridCoord) -> (gateNode: SKNode?, openedCoords: [GridCoord]) {
        pendingInput = PendingInput()
        // Keep the gate sprite around for the dissolve; openGate converts cells to floor.
        let gateNode = renderer.detachGateNode(at: coord, in: world)
        let openedCoords = world.openGate(at: coord)
        renderer.armRevealFade()
        renderer.render(world: world, focus: viewportFocus)
        renderer.setFloorNodesAlpha(0, at: openedCoords)
        resumeWorldPlayerIdle()
        captureContinueAndSave()
        return (gateNode, openedCoords)
    }

    /// Dissolves the gate with sparkles while connecting floor / room fade in.
    func revealGateEncounter(
        gateNode: SKNode?,
        openedCoords: [GridCoord],
        completion: (() -> Void)? = nil
    ) {
        if !openedCoords.isEmpty {
            SoundEffectsController.shared.play(event: "gate_opened", from: worldFx)
        }
        renderer.playGateOpenAnimation(
            gateNode: gateNode,
            floorCoords: openedCoords
        ) {
            self.isPausedForEncounter = false
            completion?()
        }
    }

    /// Opens a beaten gate: fade the world out/in with `WorldFade.duration`, then dissolve
    /// the gate with sparkles while connecting floor / room fade in (`gateOpenDuration`).
    /// Used for free-open (no minigame); puzzle wins use the overlay crossfade instead.
    func resolveGateEncounter(at coord: GridCoord, completion: (() -> Void)? = nil) {
        fadeSimulationOut { [weak self] in
            guard let self else { return }
            let prepared = self.prepareGateEncounter(at: coord)
            self.fadeSimulationIn {
                self.revealGateEncounter(
                    gateNode: prepared.gateNode,
                    openedCoords: prepared.openedCoords,
                    completion: completion
                )
            }
        }
    }

    /// Retreats the player off the gate after a timeout (gate stays closed).
    func prepareGateTimeout(approach: GridCoord) {
        world.setPlayerPosition(approach)
        pendingInput = PendingInput()
        renderer.syncEntities(world.entities)
        renderer.render(world: world, focus: viewportFocus)
        resumeWorldPlayerIdle()
        // Do not overwrite Continue — the last safe world remains before the failed attempt.
    }

    func revealGateTimeout(completion: (() -> Void)? = nil) {
        isPausedForEncounter = false
        completion?()
    }

    /// Retreats the player off the gate after a timeout (gate stays closed).
    func resolveGateTimeout(approach: GridCoord, completion: (() -> Void)? = nil) {
        prepareGateTimeout(approach: approach)
        fadeSimulationIn { [weak self] in
            self?.revealGateTimeout(completion: completion)
        }
    }

    // MARK: - Vitals / continue

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

    /// Restores the world to the last safe continue snapshot (world stays faded).
    func prepareRestoreFromContinuePoint() {
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
    }

    func revealRestoreFromContinuePoint(completion: (() -> Void)? = nil) {
        isPausedForEncounter = false
        completion?()
    }

    /// Restores the world to the last safe continue snapshot and resumes play.
    func restoreFromContinuePoint(completion: (() -> Void)? = nil) {
        prepareRestoreFromContinuePoint()
        fadeSimulationIn { [weak self] in
            self?.revealRestoreFromContinuePoint(completion: completion)
        }
    }
}
