import SpriteKit
import UIKit

extension PitBridgeScene {
    var geometry: PitBridgeGeometry {
        PitBridgeGeometry(
            sceneSize: size,
            padSize: PitArenaLayout.floorPadBounds(config: isoConfig).size,
            slotCount: max(engine.wordCount, 1)
        )
    }
    // MARK: - Arena

    func buildArena() {
        removeAllChildren()
        trayNodes = [:]
        placedTileNodes = []
        slotBoxNode = nil
        wordPromptNode = nil
        blankLetterNode = nil

        let geo = geometry
        addPad(rect: geo.leftPadRect, name: "leftPad")
        addPad(rect: geo.rightPadRect, name: "rightPad")
        addPlayer(at: CGPoint(x: geo.leftPadRect.midX, y: geo.bridgeLineY))
    }

    func addPad(rect: CGRect, name: String) {
        let root = SKNode()
        root.name = name
        root.position = CGPoint(x: rect.midX, y: rect.midY)
        root.zPosition = Self.padsZ

        if let cluster = makeFloorPadCluster(
            library: floorTileSetLibrary,
            config: isoConfig,
            using: &placementRNG
        ) {
            root.addChild(cluster)
        } else {
            let fallback = SKShapeNode(rectOf: rect.size, cornerRadius: 6)
            fallback.fillColor = padFill
            fallback.strokeColor = UIColor(white: 0.2, alpha: 1)
            fallback.lineWidth = 2
            fallback.zPosition = 0
            root.addChild(fallback)
        }
        addChild(root)
    }

    func addPlayer(at position: CGPoint) {
        playerSprite = nil
        playerFacingLeft = false
        let height = playerDisplayHeight

        if let config = playerSpriteConfig,
           spriteLibrary.animation(id: Self.playerLibraryID, named: "idle_right") != nil
            || spriteLibrary.animation(id: Self.playerLibraryID, named: "idle_down") != nil {
            let sprite = AnimatedSpriteNode(size: CGSize(width: height, height: height))
            // Sized once here: the first idle clip locks pixels-to-points for the rest.
            // Re-fitting per clip would squash jump, celebrate and Force-lift, whose trims
            // are taller than a standing pose, back down to standing height.
            sprite.fitHeight(height)
            sprite.zPosition = Self.playerZ
            sprite.name = "player"
            sprite.position = position
            addChild(sprite)
            playerNode = sprite
            playerSprite = sprite
            let correction = height * CGFloat(config.anchorCorrection) / 100
            sprite.position = CGPoint(x: position.x, y: position.y - correction)
            resumePlayerIdle()
            return
        }

        let radius = max(height * 0.28, 12)
        let fallback = SKShapeNode(circleOfRadius: radius)
        fallback.fillColor = playerFill
        fallback.strokeColor = UIColor(white: 0.9, alpha: 1)
        fallback.lineWidth = 2
        fallback.position = position
        fallback.zPosition = Self.playerZ
        fallback.name = "player"
        addChild(fallback)
        playerNode = fallback
    }

    var playerDisplayHeight: CGFloat {
        if let config = playerSpriteConfig {
            return max(
                PlaceholderFactory.spriteDisplayHeight(isoConfig: isoConfig, spriteConfig: config),
                48
            )
        }
        return max(geometry.tileSide * 1.2, 48)
    }

    func resumePlayerIdle() {
        guard playerSprite != nil else { return }
        let preferred = playerFacingLeft ? "idle_left" : "idle_right"
        let name: String
        if spriteLibrary.animation(id: Self.playerLibraryID, named: preferred) != nil {
            name = preferred
        } else {
            name = "idle_down"
        }
        playPlayerLoop(name)
    }

    func playPlayerLoop(_ name: String) {
        guard let playerSprite else { return }
        playerSprite.play(name: name, library: spriteLibrary, libraryID: Self.playerLibraryID)
    }

    func playJumpAnimation(toward target: CGPoint) {
        guard let playerSprite, let playerNode else { return }
        playerFacingLeft = target.x < playerNode.position.x - 0.5
        let name = playerFacingLeft ? "jump_left" : "jump_right"
        playerSprite.playOnce(name: name, library: spriteLibrary, libraryID: Self.playerLibraryID)
    }

    /// Loop Kam's Force-lift clip while a tray tile is held.
    func playForceLiftAnimation(toward target: CGPoint) {
        guard let playerSprite, let playerNode else { return }
        playerFacingLeft = target.x < playerNode.position.x - 0.5
        let preferred = playerFacingLeft
            ? "lifting_with_the_force_left"
            : "lifting_with_the_force_right"
        let name: String
        if spriteLibrary.animation(id: Self.playerLibraryID, named: preferred) != nil {
            name = preferred
        } else if spriteLibrary.animation(id: Self.playerLibraryID, named: "lifting_with_the_force_right") != nil {
            name = "lifting_with_the_force_right"
        } else {
            return
        }
        playPlayerLoop(name)
    }
    // MARK: - Resize

    func repositionForNewSize() {
        let geo = geometry
        if let left = childNode(withName: "leftPad") {
            left.position = CGPoint(x: geo.leftPadRect.midX, y: geo.leftPadRect.midY)
        }
        if let right = childNode(withName: "rightPad") {
            right.position = CGPoint(x: geo.rightPadRect.midX, y: geo.rightPadRect.midY)
        }
        for (index, node) in placedTileNodes.enumerated() {
            node.position = geo.slotCenter(index)
        }
        if let slotBoxNode {
            slotBoxNode.position = geo.slotCenter(engine.roundIndex)
        }
        wordPromptNode?.position = geo.wordPromptCenter
        let trayChoices = engine.choices
        for (index, choice) in trayChoices.enumerated() {
            trayNodes[choice.id]?.position = geo.trayCenter(index)
        }
        if !isJumping, placedTileNodes.isEmpty, let playerNode {
            playerNode.position = CGPoint(x: geo.leftPadRect.midX, y: geo.bridgeLineY)
        } else if !isJumping, let last = placedTileNodes.last, let playerNode {
            playerNode.position = last.position
        }
    }

    // MARK: - Audio

    func playDucked(event: String, from table: SoundEffectTable) {
        guard let trackID = table.trackID(for: event) else { return }
        SoundEffectsController.shared.play(trackID: trackID)
        BackgroundMusicController.shared.duckForPhoneticCue(
            duration: SoundEffectsController.shared.cueDuration(of: trackID)
        )
    }

    /// Letter sound ("buh") when a tray tile is picked up.
    func playLetterPronunciation(_ letter: String) {
        guard let trackID = LetterSoundCatalog.pronunciationTrackID(for: letter) else { return }
        removeAction(forKey: Self.letterCueActionKey)
        SoundEffectsController.shared.play(trackID: trackID)
    }

    /// After a correct drop: pronunciation, then letter name, then `continuation`.
    func playCorrectLetterCues(letter: String, then continuation: @escaping () -> Void) {
        var steps: [SKAction] = []
        appendLetterTrackSteps(
            to: &steps,
            trackID: LetterSoundCatalog.pronunciationTrackID(for: letter)
        )
        appendLetterTrackSteps(
            to: &steps,
            trackID: LetterSoundCatalog.nameTrackID(for: letter)
        )
        steps.append(SKAction.run(continuation))
        removeAction(forKey: Self.letterCueActionKey)
        run(SKAction.sequence(steps), withKey: Self.letterCueActionKey)
    }

    func appendLetterTrackSteps(to steps: inout [SKAction], trackID: String?) {
        guard let trackID, !trackID.isEmpty else { return }
        let duration = SoundEffectsController.shared.cueDuration(of: trackID)
        steps.append(SKAction.run {
            SoundEffectsController.shared.play(trackID: trackID)
        })
        steps.append(SKAction.wait(forDuration: duration))
    }
}
