import SpriteKit

extension CombatScene {
    // MARK: - Layout

    /// 40% screen height × 1.2 (20% larger).
    var playerSpriteHeight: CGFloat { size.height * 0.48 }

    /// 2× world height, then −30%, then ×1.2 (`2 × 0.7 × 1.2 × wallHeight × scale`).
    var enemySpriteHeight: CGFloat {
        guard let enemySprite else { return size.height * 0.084 }
        return 1.4 * PlaceholderFactory.spriteDisplayScaleMultiplier
            * wallHeight * CGFloat(enemySprite.config.scale)
    }

    /// Feet (sprite bottom-middle) sit on the view's bottom-middle.
    var playerPosition: CGPoint {
        CGPoint(x: size.width * 0.5, y: 0)
    }

    func buildArena() {
        playerNode?.removeFromParent()
        enemyNode?.removeFromParent()

        let player = AnimatedSpriteNode(
            size: CGSize(width: playerSpriteHeight, height: playerSpriteHeight)
        )
        player.fitHeight(playerSpriteHeight)
        player.zPosition = 10
        player.name = "player"
        addChild(player)
        playerNode = player
        // `show` applies the V-inversion scale so feet stay at position and the
        // body extends upward onto the screen (raw texture assignment does not).
        if combatSprite != nil {
            player.show(
                name: playerSwingAnimationName,
                library: spriteLibrary,
                libraryID: playerCombatLibraryID
            )
            player.fitHeight(playerSpriteHeight)
        }
        player.position = playerPosition

        let enemy = AnimatedSpriteNode(
            size: CGSize(width: enemySpriteHeight, height: enemySpriteHeight)
        )
        enemy.zPosition = 10
        enemy.name = "enemy"
        addChild(enemy)
        enemyNode = enemy
        if let enemySprite,
           spriteLibrary.animation(id: enemySprite.id, named: "idle_down") != nil {
            enemy.play(
                name: "idle_down",
                library: spriteLibrary,
                libraryID: enemySprite.id
            )
        }
        // Size + place after texture is known so the top-middle pixel sits on the view top.
        placeEnemyAtTopOfView()
    }

    func placeEnemyAtTopOfView() {
        guard let enemyNode else { return }
        pinToTopOfView(enemyNode, height: enemySpriteHeight)
    }

    func repositionArenaNodes() {
        guard let playerNode, let enemyNode else {
            buildArena()
            return
        }
        playerNode.fitHeight(playerSpriteHeight)
        playerNode.position = playerPosition
        pinToTopOfView(enemyNode, height: enemySpriteHeight)
    }

    // MARK: - Engine events

    func handle(_ event: CombatEngineEvent) {
        switch event {
        case let .sequenceCue(requiredLetter):
            playSequenceCue(requiredLetter: requiredLetter)
            // In-flight letters retarget immediately when the spoken cue changes.
            syncShotAiming()
        case let .spawnShot(id, travelSeconds, visualLetter):
            spawnShot(id: id, travelSeconds: travelSeconds, visualLetter: visualLetter)
        case let .healthChanged(health):
            combatDelegate?.combatSceneDidUpdateHealth(health)
        case .won:
            finishWin()
        case .lost:
            finishLose()
        }
    }

    func playSequenceCue(requiredLetter: String) {
        // Prefer shared letter-name tracks so combat matches wall / other letter games.
        if let shared = GraphemeSoundCatalog.nameTrackID(for: requiredLetter) {
            SoundEffectsController.shared.play(trackID: shared)
            return
        }
        // shot_types keys are uppercase catalog ids; cues may be lower / mixed case.
        if let typeFx = enemyType.shotTypes[requiredLetter.uppercased()]?.fx,
           let trackID = typeFx.trackID(for: "shoot") {
            SoundEffectsController.shared.play(trackID: trackID)
        }
    }
}
