//
//  GameSceneAnimationDriver.swift
//  Padawan Adventures
//

import SpriteKit

extension GameScene {
    /// Renders at YAML tile size with worldScale = 1, centered on the player.
    func showFixedZoomView() {
        let anchor = world.playerPosition ?? world.spawn
        viewportFocus = IsometricMath.entityScreenPosition(anchor, config: isoConfig)
        renderer.lockWorldScale(1)
        renderer.render(world: world, focus: viewportFocus)
        updatePlayerSpriteAnimation()
    }

    func applyTickResult(_ result: SimulationTickResult) {
        for enemyID in result.noticedEnemyIDs {
            onEnemyNoticed?(enemyID)
        }

        for event in result.movementEvents {
            if case .reached = event {
                SoundEffectsController.shared.play(event: "move", from: playerFx)
            }
        }

        let occupancy = result.playerDisplayCoord ?? world.playerPosition ?? world.spawn
        let displayPoint = result.playerDisplayPoint
            ?? IsometricMath.entityScreenPosition(occupancy, config: isoConfig)

        let rebuiltForStory = renderer.updateVisibleStory(for: world, focus: viewportFocus)
        if rebuiltForStory {
            viewportFocus = IsometricMath.entityScreenPosition(occupancy, config: isoConfig)
            renderer.lockWorldScale(1)
            renderer.updateViewportFocus(viewportFocus)
        } else if !gestureTracker.isPanning {
            viewportFocus = IsometricMath.focusKeepingPlayerInDeadzone(
                focus: viewportFocus,
                player: displayPoint,
                story: occupancy.story,
                maxTiles: Self.cameraDeadzoneTiles,
                config: isoConfig
            )
            renderer.updateViewportFocus(viewportFocus)
        }

        renderer.syncEntities(world.entities)

        if let player = world.entities.first(where: \.isPlayer),
           player.position.story == renderer.visibleStory {
            let sortPose = result.playerSortPose ?? FractionalGridPose(
                x: Double(occupancy.x),
                y: Double(occupancy.y),
                story: occupancy.story
            )
            renderer.updateEntityDisplayPosition(
                player,
                screenPosition: displayPoint,
                sortX: sortPose.x,
                sortY: sortPose.y,
                sortStory: sortPose.story
            )
        }

        for pose in result.enemyDisplayPoses {
            guard let entity = world.entity(id: pose.entityID),
                  entity.position.story == renderer.visibleStory else { continue }
            renderer.updateEntityDisplayPosition(
                entity,
                screenPosition: pose.screenPosition,
                sortX: pose.sortPose.x,
                sortY: pose.sortPose.y,
                sortStory: pose.sortPose.story
            )
        }

        renderer.applyAnimation(to: world.entities, frame: result.animationFrame)
        updatePlayerSpriteAnimation()
        updateEnemySpriteAnimations(poses: result.enemyDisplayPoses)
    }

    func updatePlayerSpriteAnimation() {
        guard let library = spriteLibrary,
              let sprite = renderer.playerAnimatedSprite() else { return }

        let locomotion: SpriteLocomotion
        if movement.isMoving,
           let start = movement.segmentStart,
           let end = movement.segmentEnd {
            let dx = end.x - start.x
            let dy = end.y - start.y
            if let facing = CompassDirection(dx: dx, dy: dy) {
                playerFacing = facing
            }
            locomotion = .walk
        } else {
            locomotion = .idle
        }

        let name = playerFacing.animationName(locomotion: locomotion)
        sprite.play(name: name, library: library)
        // Fall back to idle for the same facing when a walk sheet is not loaded yet.
        if sprite.currentAnimationName != name {
            let idleName = playerFacing.animationName(locomotion: .idle)
            sprite.play(name: idleName, library: library)
        }
    }

    func updateEnemySpriteAnimations(poses: [EntityDisplayPose]) {
        guard let library = spriteLibrary else { return }

        let liveIDs = Set(poses.map(\.entityID))
        enemyFacings = enemyFacings.filter { liveIDs.contains($0.key) }

        for pose in poses {
            guard let entity = world.entity(id: pose.entityID),
                  let typeID = entity.enemyTypeID,
                  let resolved = enemyConfig.spriteConfig(for: typeID),
                  let sprite = renderer.enemyAnimatedSprite(id: pose.entityID) else { continue }

            if let facing = pose.facing {
                enemyFacings[pose.entityID] = facing
            }
            let facing = enemyFacings[pose.entityID] ?? .down
            let locomotion: SpriteLocomotion = pose.isMoving ? .walk : .idle

            let name = facing.animationName(locomotion: locomotion)
            sprite.play(name: name, library: library, libraryID: resolved.id)
            // Fall back to the same facing's idle clip when a walk sheet is missing.
            if sprite.currentAnimationName != name {
                sprite.play(
                    name: facing.animationName(locomotion: .idle),
                    library: library,
                    libraryID: resolved.id
                )
            }
        }
    }
}
