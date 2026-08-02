//
//  GameScenePickupResolver.swift
//  Padawan Adventures
//

import SpriteKit

extension GameScene {
    /// Returns `true` when simulation should pause (treasure only).
    @discardableResult
    func beginPickupResolution(pickupID: UUID) -> Bool {
        guard let pickup = world.entity(id: pickupID),
              let kind = pickup.pickupKind else { return false }

        switch kind {
        case .health, .energy:
            resolveHealthOrEnergyPickup(id: pickupID, kind: kind)
            return false
        case .treasure:
            isResolvingPickup = true
            pendingInput = PendingInput()
            resolveTreasurePickup(id: pickupID)
            return true
        }
    }

    func resolveHealthOrEnergyPickup(id: UUID, kind: PickupKind) {
        // Remove immediately so contact can't re-fire and syncEntities won't recreate the sprite.
        // Collect bounce/fade runs on the detached node while the sim keeps ticking.
        _ = world.removeEntity(id: id)
        switch kind {
        case .health:
            world.healthCount += 1
        case .energy:
            if EnergyMechanic.isEnabled {
                world.energyCount += 1
            }
        case .treasure:
            break
        }
        onPickupCollected?(kind)
        renderer.playPickupCollectAnimation(id: id) { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.captureContinueAndSave()
            }
        }
    }

    func resolveTreasurePickup(id: UUID) {
        _ = world.removeEntity(id: id)
        renderer.syncEntities(world.entities)
        renderer.shakeWorld { [weak self] in
            guard let self else { return }
            self.playTreasureCelebration { [weak self] in
                guard let self else { return }
                self.renderer.fadeWorld { [weak self] in
                    guard let self else { return }
                    // Win path deletes the mid-run save; do not schedule a racing rewrite.
                    self.onTreasureCollected?()
                }
            }
        }
    }

    /// Plays Kam's `celebrate_down` clip twice, then invokes `completion`.
    func playTreasureCelebration(completion: @escaping () -> Void) {
        onTreasureCelebrationStarted?()
        guard let library = spriteLibrary,
              let sprite = renderer.playerAnimatedSprite() else {
            completion()
            return
        }
        sprite.play(
            name: "celebrate_down",
            library: library,
            count: 2,
            completion: completion
        )
    }
}
