import SpriteKit
import UIKit

/// One-shot green/blue particle swirl plus a spinning blue ground reticule that
/// marks a tap-to-move floor target.
///
/// The reticule sits on the floor diamond and fades in then out over 0.75s while
/// spinning. Particles start on the same tile (slightly above the art so they
/// are never hidden under it) and spiral upward to 20% of the player sprite's
/// height over the same 0.75s while fading out.
@MainActor
enum TapTargetSwirl {
    static let nodeName = "tapTargetSwirl"
    static let duration: TimeInterval = 0.75
    /// Visual rise as a fraction of the player sprite's display height.
    static let riseHeightFraction: CGFloat = 0.2
    /// Painter-order rise as a fraction of the floor→player z gap.
    static let zProgressFraction: CGFloat = 0.2
    /// Above floor tile sprites (`0.02`) so the first frame overlays the diamond.
    static let floorOverlayZ: CGFloat = 0.05
    static let orbitTurns: CGFloat = 2.5
    /// Orbit size as a fraction of the floor diamond.
    static let orbitRadiusFraction: CGFloat = 0.38
    /// Multiplier on `orbitRadiusFraction` at t = 0 (50% smaller than the original orbit).
    static let startRadiusScale: CGFloat = 0.5
    /// Multiplier on `orbitRadiusFraction` at t = 1 (10% smaller than the original orbit).
    static let endRadiusScale: CGFloat = 0.9
    static let particleLifetime: TimeInterval = 0.5
    static let birthRate: CGFloat = 84

    static let reticuleName = "tapTargetReticule"
    static let reticuleSpinnerName = "tapTargetReticuleSpinner"
    static let reticuleSpinTurns: CGFloat = 1.75
    /// Outer ring radius as a fraction of tile width (half the original 0.41).
    static let reticuleRadiusFraction: CGFloat = 0.205
    /// Stroke width as a fraction of tile width (half of the previous 0.03375).
    static let reticuleLineFraction: CGFloat = 0.016875
    /// Uniform scale at the end of the animation (a slight shrink from 1).
    static let reticuleEndScale: CGFloat = 0.88

    static let green = UIColor(red: 0.20, green: 0.84, blue: 0.29, alpha: 1)
    static let blue = UIColor(red: 0.35, green: 0.78, blue: 0.98, alpha: 1)

    static func riseDistance(playerSpriteHeight: CGFloat) -> CGFloat {
        playerSpriteHeight * riseHeightFraction
    }

    /// Orbit scale at `progress` (0 = start radius, 1 = end radius).
    static func orbitScale(progress: CGFloat) -> CGFloat {
        startRadiusScale + progress * (endRadiusScale - startRadiusScale)
    }

    /// zPosition at `progress` (0 = floor overlay, 1 = player sprite).
    static func zPosition(startZ: CGFloat, playerZ: CGFloat, progress: CGFloat) -> CGFloat {
        startZ + progress * (playerZ - startZ)
    }

    static func play(
        in parent: SKNode,
        at position: CGPoint,
        startZ: CGFloat,
        playerZ: CGFloat,
        tileWidth: CGFloat,
        tileHeight: CGFloat,
        playerSpriteHeight: CGFloat
    ) {
        let wrapper = SKNode()
        wrapper.name = nodeName
        wrapper.position = position
        wrapper.zPosition = startZ
        parent.addChild(wrapper)

        let reticule = makeReticule(tileWidth: tileWidth, tileHeight: tileHeight)
        wrapper.addChild(reticule)
        playReticuleAnimation(on: reticule, spinner: reticuleSpinner(in: reticule))

        let swirlHost = SKNode()
        swirlHost.zPosition = 0.01
        wrapper.addChild(swirlHost)

        let rise = riseDistance(playerSpriteHeight: playerSpriteHeight)
        let endZ = zPosition(startZ: startZ, playerZ: playerZ, progress: zProgressFraction)
        let baseRadiusX = tileWidth * orbitRadiusFraction
        let baseRadiusY = tileHeight * orbitRadiusFraction
        let startScale = startRadiusScale

        let greenEmitter = makeEmitter(color: green, name: "tapTargetGreen", referenceHeight: playerSpriteHeight)
        let blueEmitter = makeEmitter(color: blue, name: "tapTargetBlue", referenceHeight: playerSpriteHeight)
        // Leave particles in the host so they trail along the orbit instead of
        // clumping on the two emitter points.
        greenEmitter.targetNode = swirlHost
        blueEmitter.targetNode = swirlHost
        greenEmitter.position = CGPoint(x: baseRadiusX * startScale, y: 0)
        blueEmitter.position = CGPoint(x: -baseRadiusX * startScale, y: 0)
        swirlHost.addChild(greenEmitter)
        swirlHost.addChild(blueEmitter)

        let motion = SKAction.customAction(withDuration: duration) { node, elapsed in
            let t = CGFloat(elapsed / duration)
            let eased = 1 - (1 - t) * (1 - t)
            let angle = t * orbitTurns * (.pi * 2)
            let scale = orbitScale(progress: eased)
            let radiusX = baseRadiusX * scale
            let radiusY = baseRadiusY * scale
            greenEmitter.position = CGPoint(x: radiusX * cos(angle), y: radiusY * sin(angle))
            blueEmitter.position = CGPoint(
                x: radiusX * cos(angle + .pi),
                y: radiusY * sin(angle + .pi)
            )
            // Spray along the tangent so new particles fill the gap behind the orbit.
            greenEmitter.emissionAngle = angle + .pi / 2
            blueEmitter.emissionAngle = angle + .pi / 2 + .pi
            node.position = CGPoint(x: 0, y: rise * eased)
            node.zPosition = 0.01 + (endZ - startZ) * eased
            let fade = max(1 - t, 0)
            greenEmitter.particleBirthRate = birthRate * fade
            blueEmitter.particleBirthRate = birthRate * fade
        }

        swirlHost.run(motion)
        wrapper.run(
            .sequence([
                .wait(forDuration: duration + particleLifetime),
                .removeFromParent(),
            ]),
            withKey: nodeName
        )
    }

    /// Isometric ground reticle: squash stays world-aligned so the ellipse reads as
    /// sitting on the floor while the marks spin in the ground plane.
    static func makeReticule(tileWidth: CGFloat, tileHeight: CGFloat) -> SKNode {
        let root = SKNode()
        root.name = reticuleName
        root.alpha = 0

        let squash = SKNode()
        squash.yScale = tileWidth > 0 ? tileHeight / tileWidth : 1

        let spinner = SKNode()
        spinner.name = reticuleSpinnerName
        squash.addChild(spinner)
        root.addChild(squash)

        let outerR = tileWidth * reticuleRadiusFraction
        let innerR = outerR * 0.52
        let line = max(tileWidth * reticuleLineFraction, 0.6)
        let glow = max(tileWidth * 0.02625, 0.85)

        let outerRect = CGRect(x: -outerR, y: -outerR, width: outerR * 2, height: outerR * 2)
        let solidOuter = CGPath(ellipseIn: outerRect, transform: nil)
        let outerPath = solidOuter.copy(
            dashingWithPhase: 0,
            lengths: [tileWidth * 0.07, tileWidth * 0.04]
        ) ?? solidOuter
        let outer = makeGlowStroke(path: outerPath, lineWidth: line, color: blue, glowWidth: glow)
        outer.blendMode = .add
        spinner.addChild(outer)

        let innerRect = CGRect(x: -innerR, y: -innerR, width: innerR * 2, height: innerR * 2)
        let inner = makeGlowStroke(
            path: CGPath(ellipseIn: innerRect, transform: nil),
            lineWidth: line * 0.75,
            color: blue,
            glowWidth: glow * 0.7
        )
        inner.blendMode = .add
        spinner.addChild(inner)

        for i in 0..<4 {
            let angle = CGFloat(i) * (.pi / 2)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: cos(angle) * innerR * 0.2, y: sin(angle) * innerR * 0.2))
            path.addLine(to: CGPoint(x: cos(angle) * innerR * 0.85, y: sin(angle) * innerR * 0.85))
            let tick = makeGlowStroke(path: path, lineWidth: line, color: blue, glowWidth: glow * 0.6)
            tick.blendMode = .add
            spinner.addChild(tick)
        }

        let pip = SKShapeNode(circleOfRadius: max(tileWidth * 0.0175, 0.6))
        pip.fillColor = blue
        pip.strokeColor = .clear
        pip.glowWidth = glow * 0.4
        pip.blendMode = .add
        spinner.addChild(pip)

        return root
    }

    static func reticuleSpinner(in reticule: SKNode) -> SKNode? {
        reticule.children.first?.childNode(withName: reticuleSpinnerName)
    }

    static func playReticuleAnimation(on reticule: SKNode, spinner: SKNode?) {
        reticule.alpha = 0
        let fadeIn = SKAction.fadeAlpha(to: 1, duration: duration * 0.28)
        fadeIn.timingMode = .easeOut
        let fadeOut = SKAction.fadeOut(withDuration: duration * 0.36)
        fadeOut.timingMode = .easeIn
        reticule.run(
            .sequence([
                fadeIn,
                .wait(forDuration: duration * 0.36),
                fadeOut,
            ]),
            withKey: reticuleName
        )

        let shrink = SKAction.scale(to: reticuleEndScale, duration: duration)
        shrink.timingMode = .easeIn
        reticule.run(shrink, withKey: "\(reticuleName)Shrink")

        guard let spinner else { return }
        let revolutionDuration = duration / TimeInterval(reticuleSpinTurns)
        let revolution = SKAction.rotate(byAngle: .pi * 2, duration: revolutionDuration)
        revolution.timingMode = .linear
        spinner.run(.repeatForever(revolution), withKey: reticuleSpinnerName)
    }

    static func makeEmitter(color: UIColor, name: String, referenceHeight: CGFloat) -> SKEmitterNode {
        let emitter = SKEmitterNode()
        emitter.name = name
        emitter.particleTexture = SparkleEmitterFactory.particleTexture()
        emitter.particleColor = color
        emitter.particleColorBlendFactor = 1
        emitter.particleBlendMode = .add
        emitter.particleBirthRate = birthRate
        emitter.particleLifetime = CGFloat(particleLifetime)
        emitter.particleLifetimeRange = CGFloat(particleLifetime) * 0.3
        let diameter = max(referenceHeight * 0.07, 4)
        emitter.particleSize = CGSize(width: diameter, height: diameter)
        emitter.particleAlpha = 0.95
        emitter.particleAlphaSpeed = -0.95 / CGFloat(particleLifetime)
        emitter.particleScale = 1
        emitter.particleScaleRange = 0.4
        emitter.particleScaleSpeed = -1.4
        let spread = referenceHeight * 0.14
        emitter.particlePositionRange = CGVector(dx: spread, dy: spread * 0.7)
        emitter.particleSpeed = referenceHeight * 0.14
        emitter.particleSpeedRange = referenceHeight * 0.08
        emitter.emissionAngleRange = .pi * 0.9
        emitter.particleRotationRange = .pi * 2
        emitter.particleRotationSpeed = 2.4
        return emitter
    }
}
