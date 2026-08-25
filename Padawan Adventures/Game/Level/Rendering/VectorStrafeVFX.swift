import SpriteKit
import UIKit

/// Vector strafe VFX: baked southwest ship, blaster bolt, and impact burst.
@MainActor
enum VectorStrafeVFX {
    static let shipLength: CGFloat = 260
    static let boltLength: CGFloat = 86

    /// Looping flyover ship. Art already faces southwest, matching the NE→SW path.
    static func makeShip(library: SpriteLibrary? = nil) -> SKNode {
        if let library,
           let animation = library.animation(
               id: VectorSpritesConfig.libraryID,
               named: VectorSpritesConfig.flyAnimation
           ),
           !animation.frames.isEmpty
        {
            return makeSpriteShip(animation: animation)
        }
        return makePlaceholderShip()
    }

    private static func makeSpriteShip(animation: SpriteAnimation) -> SKNode {
        let node = AnimatedSpriteNode(size: .zero)
        node.name = "vectorShip"
        node.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        node.correctsUIImageVInversion = true
        node.fitWidth(shipLength)
        node.play(animation: animation, name: VectorSpritesConfig.flyAnimation)
        return node
    }

    /// Last-resort kite if the baked clip is not loaded (tests / missing assets).
    private static func makePlaceholderShip() -> SKNode {
        let root = SKNode()
        root.name = "vectorShip"

        let length = shipLength
        let halfW = length * 0.38
        let kite = CGMutablePath()
        kite.move(to: CGPoint(x: length * 0.52, y: 0))
        kite.addLine(to: CGPoint(x: length * 0.08, y: halfW))
        kite.addLine(to: CGPoint(x: -length * 0.48, y: 0))
        kite.addLine(to: CGPoint(x: length * 0.08, y: -halfW))
        kite.closeSubpath()

        let halo = SKShapeNode(path: kite)
        halo.fillColor = UIColor(red: 0.25, green: 0.75, blue: 1, alpha: 0.28)
        halo.strokeColor = UIColor(red: 0.45, green: 0.9, blue: 1, alpha: 0.7)
        halo.lineWidth = 14
        halo.glowWidth = 10
        halo.blendMode = .add
        root.addChild(halo)

        let shadow = SKShapeNode(path: kite)
        shadow.fillColor = UIColor(red: 0.05, green: 0.12, blue: 0.22, alpha: 0.55)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 6, y: -10)
        root.addChild(shadow)

        let hull = SKShapeNode(path: kite)
        hull.fillColor = UIColor(red: 0.18, green: 0.55, blue: 0.95, alpha: 1)
        hull.strokeColor = UIColor.white
        hull.lineWidth = 5
        hull.glowWidth = 2
        root.addChild(hull)

        let spar = CGMutablePath()
        spar.move(to: CGPoint(x: length * 0.52, y: 0))
        spar.addLine(to: CGPoint(x: -length * 0.48, y: 0))
        spar.move(to: CGPoint(x: length * 0.08, y: halfW))
        spar.addLine(to: CGPoint(x: length * 0.08, y: -halfW))
        let spars = SKShapeNode(path: spar)
        spars.strokeColor = UIColor.white.withAlphaComponent(0.9)
        spars.lineWidth = 3
        spars.lineCap = .round
        root.addChild(spars)

        let cell = CGMutablePath()
        cell.move(to: CGPoint(x: length * 0.52, y: 0))
        cell.addLine(to: CGPoint(x: length * 0.08, y: halfW))
        cell.addLine(to: CGPoint(x: length * 0.08, y: 0))
        cell.closeSubpath()
        let highlight = SKShapeNode(path: cell)
        highlight.fillColor = UIColor(red: 0.7, green: 0.95, blue: 1, alpha: 0.55)
        highlight.strokeColor = .clear
        root.addChild(highlight)

        let canopy = SKShapeNode(circleOfRadius: length * 0.055)
        canopy.fillColor = UIColor(red: 1, green: 0.95, blue: 0.55, alpha: 1)
        canopy.strokeColor = .white
        canopy.lineWidth = 2
        canopy.position = CGPoint(x: length * 0.08, y: 0)
        root.addChild(canopy)

        let tail = CGMutablePath()
        tail.move(to: CGPoint(x: -length * 0.48, y: 0))
        tail.addLine(to: CGPoint(x: -length * 0.62, y: 16))
        tail.addLine(to: CGPoint(x: -length * 0.78, y: -6))
        tail.addLine(to: CGPoint(x: -length * 0.7, y: 10))
        let ribbon = SKShapeNode(path: tail)
        ribbon.strokeColor = UIColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)
        ribbon.lineWidth = 4
        ribbon.lineJoin = .round
        ribbon.lineCap = .round
        ribbon.glowWidth = 2
        root.addChild(ribbon)

        root.yScale = 0.72
        return root
    }

    /// Short thick cyan-white bolt matching the concept art, pointing local +X.
    static func makeBolt() -> SKNode {
        let root = SKNode()
        root.name = "vectorBolt"
        let length = boltLength

        addGlowLine(
            to: root,
            from: CGPoint(x: -length * 0.38, y: 0),
            to: CGPoint(x: length * 0.42, y: 0),
            width: 18,
            color: UIColor(red: 0.25, green: 0.7, blue: 1, alpha: 0.22)
        )
        addGlowLine(
            to: root,
            from: CGPoint(x: -length * 0.36, y: 0),
            to: CGPoint(x: length * 0.44, y: 0),
            width: 10,
            color: UIColor(red: 0.35, green: 0.85, blue: 1, alpha: 0.55)
        )
        addGlowLine(
            to: root,
            from: CGPoint(x: -length * 0.34, y: 0),
            to: CGPoint(x: length * 0.46, y: 0),
            width: 5,
            color: UIColor(red: 0.7, green: 0.95, blue: 1, alpha: 0.95)
        )
        addGlowLine(
            to: root,
            from: CGPoint(x: -length * 0.3, y: 0),
            to: CGPoint(x: length * 0.4, y: 0),
            width: 2.2,
            color: .white
        )

        let head = SKShapeNode(ellipseOf: CGSize(width: 16, height: 11))
        head.fillColor = UIColor(red: 0.85, green: 0.98, blue: 1, alpha: 1)
        head.strokeColor = UIColor(red: 0.35, green: 0.85, blue: 1, alpha: 0.9)
        head.lineWidth = 1
        head.glowWidth = 2
        head.position = CGPoint(x: length * 0.46, y: 0)
        root.addChild(head)

        let tip = SKShapeNode(circleOfRadius: 2.4)
        tip.fillColor = .white
        tip.strokeColor = .clear
        tip.blendMode = .add
        tip.position = CGPoint(x: length * 0.54, y: 0)
        root.addChild(tip)

        addArc(
            to: root,
            points: [
                CGPoint(x: -length * 0.12, y: 3),
                CGPoint(x: length * 0.02, y: 9),
                CGPoint(x: length * 0.16, y: 4),
                CGPoint(x: length * 0.3, y: 8),
                CGPoint(x: length * 0.42, y: 2),
            ]
        )
        addArc(
            to: root,
            points: [
                CGPoint(x: -length * 0.1, y: -3),
                CGPoint(x: length * 0.06, y: -8),
                CGPoint(x: length * 0.2, y: -3),
                CGPoint(x: length * 0.34, y: -7),
                CGPoint(x: length * 0.44, y: -2),
            ]
        )
        addArc(
            to: root,
            points: [
                CGPoint(x: length * 0.28, y: 5),
                CGPoint(x: length * 0.38, y: 11),
                CGPoint(x: length * 0.48, y: 3),
            ]
        )
        addArc(
            to: root,
            points: [
                CGPoint(x: length * 0.3, y: -4),
                CGPoint(x: length * 0.4, y: -10),
                CGPoint(x: length * 0.5, y: -2),
            ]
        )

        addOrb(to: root, at: CGPoint(x: -length * 0.42, y: 0))
        return root
    }

    static func playExplosion(in parent: SKNode, at position: CGPoint) {
        let burst = SKNode()
        burst.position = position
        burst.zPosition = 20_000_200
        parent.addChild(burst)

        for (index, radius) in [10, 18, 28].enumerated() {
            let ring = SKShapeNode(circleOfRadius: CGFloat(radius))
            ring.fillColor = .clear
            ring.strokeColor = index == 0
                ? UIColor(red: 1, green: 0.95, blue: 0.7, alpha: 0.95)
                : UIColor(red: 0.35, green: 0.85, blue: 1, alpha: 0.85)
            ring.lineWidth = index == 0 ? 3.5 : 2
            ring.glowWidth = 3
            ring.setScale(0.25)
            burst.addChild(ring)
            let delay = TimeInterval(index) * 0.04
            ring.run(.sequence([
                .wait(forDuration: delay),
                .group([
                    .scale(to: 1.35, duration: 0.22),
                    .fadeOut(withDuration: 0.22),
                ]),
            ]))
        }

        let core = SKShapeNode(circleOfRadius: 8)
        core.fillColor = UIColor(red: 1, green: 0.92, blue: 0.55, alpha: 0.95)
        core.strokeColor = UIColor(red: 0.4, green: 0.85, blue: 1, alpha: 0.8)
        core.lineWidth = 1.5
        burst.addChild(core)
        core.run(.group([
            .scale(to: 2.4, duration: 0.2),
            .fadeOut(withDuration: 0.2),
        ]))

        let sparkles = SparkleEmitterFactory.makeBurstNode(
            config: HighlightConfig(
                color: "#7FDBFF",
                birthRate: 80,
                lifetime: 0.45,
                radius: 0.7,
                particleSize: 0.16,
                alpha: 0.95,
                yOffset: 0
            ),
            referenceHeight: 42,
            particleCount: 18
        )
        burst.addChild(sparkles)

        burst.run(.sequence([
            .wait(forDuration: 0.55),
            .removeFromParent(),
        ]))
    }

    private static func addGlowLine(
        to parent: SKNode,
        from: CGPoint,
        to: CGPoint,
        width: CGFloat,
        color: UIColor
    ) {
        let path = CGMutablePath()
        path.move(to: from)
        path.addLine(to: to)
        let line = SKShapeNode(path: path)
        line.strokeColor = color
        line.lineWidth = width
        line.lineCap = .round
        line.glowWidth = width * 0.35
        if color.cgColor.alpha < 0.9 {
            line.blendMode = .add
        }
        parent.addChild(line)
    }

    private static func addArc(to parent: SKNode, points: [CGPoint]) {
        guard points.count >= 2 else { return }
        let path = CGMutablePath()
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        let arc = SKShapeNode(path: path)
        arc.strokeColor = UIColor(red: 0.45, green: 0.88, blue: 1, alpha: 0.9)
        arc.lineWidth = 1.4
        arc.lineJoin = .miter
        arc.glowWidth = 1.2
        arc.blendMode = .add
        parent.addChild(arc)
    }

    private static func addOrb(to parent: SKNode, at origin: CGPoint) {
        let halo = SKShapeNode(circleOfRadius: 11)
        halo.fillColor = UIColor(red: 0.3, green: 0.8, blue: 1, alpha: 0.2)
        halo.strokeColor = .clear
        halo.blendMode = .add
        halo.position = origin
        parent.addChild(halo)

        for (dx, dy, radius) in [(0.0, 4.0, 5.5), (4.0, -1.5, 5.0), (-3.5, -2.5, 4.5)] as [(CGFloat, CGFloat, CGFloat)] {
            let swirl = SKShapeNode(circleOfRadius: radius)
            swirl.fillColor = .clear
            swirl.strokeColor = UIColor(red: 0.55, green: 0.9, blue: 1, alpha: 0.85)
            swirl.lineWidth = 1.6
            swirl.glowWidth = 1
            swirl.position = CGPoint(x: origin.x + dx, y: origin.y + dy)
            parent.addChild(swirl)
        }

        let core = SKShapeNode(circleOfRadius: 2.6)
        core.fillColor = .white
        core.strokeColor = .clear
        core.blendMode = .add
        core.position = origin
        parent.addChild(core)
    }
}
