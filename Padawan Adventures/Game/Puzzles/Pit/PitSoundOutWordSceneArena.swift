import SpriteKit
import UIKit

extension PitSoundOutWordScene {
    var geometry: PitSoundOutWordGeometry {
        PitSoundOutWordGeometry(
            sceneSize: size,
            padSize: PitArenaLayout.floorPadBounds(config: isoConfig).size,
            stepCount: max(engine.targetGraphemes.count, 1)
        )
    }

    // MARK: - Arena

    func buildArena() {
        removeAllChildren()
        candidateNodes = []
        landedTileNodes = []
        promptNode = nil
        wordGraphemeNodes = []

        let geo = geometry
        addPad(rect: geo.leftPadRect, name: "leftPad")
        addPad(rect: geo.rightPadRect, name: "rightPad")
        addPlayer(at: CGPoint(x: geo.leftPadRect.midX, y: geo.leftPadRect.midY))
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

    /// Loop the jump clip for the length of a Kam drag.
    func playJumpLoop(facingLeft: Bool) {
        guard playerSprite != nil else { return }
        playerFacingLeft = facingLeft
        let name = facingLeft ? "jump_left" : "jump_right"
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
        promptNode?.position = geo.promptCenter

        for node in landedTileNodes {
            let step = (node.userData?["step"] as? NSNumber)?.intValue
                ?? (node.userData?["step"] as? Int)
                ?? 0
            let candidate = (node.userData?["index"] as? NSNumber)?.intValue
                ?? (node.userData?["index"] as? Int)
                ?? 0
            let count = (node.userData?["count"] as? NSNumber)?.intValue
                ?? (node.userData?["count"] as? Int)
                ?? 1
            node.position = geo.candidateCenter(step: step, candidate: candidate, count: count)
        }

        let count = candidateNodes.count
        for (index, node) in candidateNodes.enumerated() {
            let step = (node.userData?["step"] as? Int) ?? (engine.currentIndex ?? 0)
            node.position = geo.candidateCenter(step: step, candidate: index, count: count)
        }

        if !isJumping, !isDraggingPlayer, let playerNode {
            if let last = landedTileNodes.last {
                playerNode.position = last.position
            } else {
                playerNode.position = CGPoint(x: geo.leftPadRect.midX, y: geo.leftPadRect.midY)
            }
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
}
