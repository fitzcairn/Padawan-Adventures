import SpriteKit
import UIKit

extension CombatDeflectScene {
    // MARK: - VFX

    func playDamage(at position: CGPoint) {
        SoundEffectsController.shared.play(event: "damage", from: playerFx)
        flashNode(playerNode, color: .orange, actionKey: playerFlashActionKey)

        let highlight = HighlightConfig.combatImpact
        let referenceHeight = max(orbBaseSize, playerSpriteHeight * 0.3)
        let burst = SparkleEmitterFactory.makeBurstNode(
            config: highlight,
            referenceHeight: referenceHeight
        )
        burst.position = position
        burst.zPosition = Layer.vfx
        addChild(burst)

        let linger = max(highlight.lifetime * 1.6, 0.7)
        burst.run(.sequence([
            .wait(forDuration: linger),
            .removeFromParent(),
        ]))
    }

    /// Total length of the combat swing clip (used to time the deflect flash).
    func swingAnimationDurationSeconds() -> TimeInterval {
        guard let animation = spriteLibrary.animation(
            id: playerCombatLibraryID,
            named: playerSwingAnimationName
        ), !animation.frames.isEmpty else {
            return 0
        }
        return animation.frames.reduce(0) { $0 + $1.duration }
    }

    /// Quickly expanding radial flash on the tapped ring's rim nearest the projectile (0.3s).
    func playLightsaberDeflectFlash(ring: CombatDeflectRing, projectilePosition: CGPoint) {
        let flash = SKSpriteNode(texture: Self.lightsaberFlashTexture())
        let base = max(playerSpriteHeight * 0.4, 48)
        flash.size = CGSize(width: base, height: base)
        flash.position = geometry.borderPoint(on: ring, nearestTo: projectilePosition)
        flash.zPosition = Layer.vfx
        // Additive so the blue-white core reads as a bright saber bloom.
        flash.blendMode = .add
        flash.setScale(0.12)
        flash.alpha = 1
        addChild(flash)

        let duration: TimeInterval = 0.3
        flash.run(.sequence([
            .group([
                .scale(to: 5.5, duration: duration),
                .fadeOut(withDuration: duration),
            ]),
            .removeFromParent(),
        ]))
    }

    /// Bright blue-white core falling off to transparency at the rim. Drawn once and reused.
    private static var cachedLightsaberFlashTexture: SKTexture?

    private static func lightsaberFlashTexture() -> SKTexture {
        if let cachedLightsaberFlashTexture {
            return cachedLightsaberFlashTexture
        }
        let size = CGSize(width: 256, height: 256)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            cg.clear(CGRect(origin: .zero, size: size))
            let colors = [
                UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1).cgColor,
                UIColor(red: 0.75, green: 0.92, blue: 1.0, alpha: 1).cgColor,
                UIColor(red: 0.35, green: 0.7, blue: 1.0, alpha: 0.75).cgColor,
                UIColor(red: 0.15, green: 0.45, blue: 1.0, alpha: 0).cgColor,
            ] as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 0.2, 0.5, 1] as [CGFloat]
            ) else {
                return
            }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            cg.drawRadialGradient(
                gradient,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: size.width / 2,
                options: []
            )
        }
        let texture = SKTexture(image: image)
        cachedLightsaberFlashTexture = texture
        return texture
    }

    func playExplosion(at position: CGPoint) {
        SoundEffectsController.shared.play(event: "slash_hit", from: playerFx)
        let circle = SKShapeNode(circleOfRadius: 12)
        circle.fillColor = .yellow
        circle.strokeColor = UIColor.orange
        circle.lineWidth = 2
        circle.position = position
        circle.zPosition = Layer.vfx
        addChild(circle)

        let grow = SKAction.scale(to: 3.5, duration: 0.2)
        let fade = SKAction.fadeOut(withDuration: 0.2)
        circle.run(SKAction.group([grow, fade])) {
            circle.removeFromParent()
        }
    }

    // MARK: - End states

    func finishWin(starsAwarded: Int) {
        guard !didEnd else { return }
        didEnd = true
        GameLogger.mark(.combat, "deflect win (stars: \(starsAwarded))")
        engine.end()
        removeAction(forKey: nextOrbActionKey)
        removeAction(forKey: deflectFlashActionKey)
        removeOrbNode()
        stopCombatLoop()
        SoundEffectsController.shared.playCommon(event: "win")
        deflectDelegate?.combatDeflectSceneDidWin(starsAwarded: starsAwarded)
    }

    func finishLose() {
        guard !didEnd else { return }
        didEnd = true
        GameLogger.mark(.combat, "deflect loss")
        engine.end()
        removeAction(forKey: nextOrbActionKey)
        removeAction(forKey: deflectFlashActionKey)
        removeOrbNode()
        stopCombatLoop()
        SoundEffectsController.shared.playCommon(event: "lose")
        deflectDelegate?.combatDeflectSceneDidLose()
    }

    func stopCombatLoop() {
        SoundEffectsController.shared.stopLoop(trackID: activeLoopTrackID)
        activeLoopTrackID = nil
        clearCombatMix()
    }

    func clearCombatMix() {
        SoundEffectsController.shared.setCombatMixActive(false)
        BackgroundMusicController.shared.setCombatMixActive(false)
    }
}
