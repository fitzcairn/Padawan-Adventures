import SpriteKit

extension CombatDeflectScene {
    // MARK: - Layout

    /// 40% screen height × 1.2 (20% larger) — same as the slash arena.
    var playerSpriteHeight: CGFloat { size.height * 0.48 }

    /// 2× world height, then −30% (`2 × 0.7 × wallHeight × scale`).
    var enemySpriteHeight: CGFloat {
        guard let enemySprite else { return size.height * 0.084 }
        return 1.4 * wallHeight * CGFloat(enemySprite.config.scale)
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
        player.zPosition = Layer.sprites
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
        cachedPlayerWidth = nil

        let enemy = AnimatedSpriteNode(
            size: CGSize(width: enemySpriteHeight, height: enemySpriteHeight)
        )
        enemy.zPosition = Layer.sprites
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

        ringLayer.removeFromParent()
        ringLayer = SKNode()
        addChild(ringLayer)
        // Rings need the fitted player texture to measure its visible width.
        rebuildRings()
        buildMonsterHPBar()
    }

    func placeEnemyAtTopOfView() {
        guard let enemyNode else { return }
        pinToTopOfView(enemyNode, height: enemySpriteHeight)
    }

    /// Geometry is derived fresh so it always matches the current scene size and
    /// the fitted player sprite.
    var geometry: CombatDeflectGeometry {
        CombatDeflectGeometry(
            sceneSize: size,
            squash: isoSquash,
            playerSpriteWidth: measuredPlayerWidth
        )
    }

    /// Measuring opaque width scans the texture's pixels, so it is cached until the
    /// player sprite is refitted (`geometry` is read on every touch).
    var measuredPlayerWidth: CGFloat {
        if let cachedPlayerWidth { return cachedPlayerWidth }
        guard let playerNode else { return playerSpriteHeight }
        let width = opaqueContentWidthPoints(for: playerNode)
        cachedPlayerWidth = width
        return width
    }
}
