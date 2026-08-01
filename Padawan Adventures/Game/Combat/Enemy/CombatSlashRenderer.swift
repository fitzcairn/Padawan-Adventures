import SpriteKit
import UIKit

extension CombatScene {
    func updateSlashLine() {
        guard slashPoints.count >= 2 else { return }
        let path = makeLightsaberSlashPath(from: slashPoints)
        if slashLine != nil, !slashStrokes.isEmpty {
            for stroke in slashStrokes {
                stroke.path = path
            }
            return
        }
        let slash = makeLightsaberSlashNode(path: path)
        slashStrokes = slash.children.compactMap { $0 as? SKShapeNode }
        slashContainerBuildCount += 1
        addChild(slash)
        slashLine = slash
    }

    /// Test seam: drives `updateSlashLine` without synthesising `UITouch` values.
    func updateSlashLineForTesting(points: [CGPoint]) {
        slashPoints = points
        updateSlashLine()
    }

    /// Also used as a test seam after `updateSlashLineForTesting`.
    func clearSlashLine() {
        guard let slash = slashLine else { return }
        slashLine = nil
        slashStrokes = []
        slash.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: slashFadeOutSeconds),
            SKAction.removeFromParent(),
        ]))
    }

    /// Quadratic arc from first→last sample, bulged through the swipe midpoint for a saber slash.
    func makeLightsaberSlashPath(from points: [CGPoint]) -> CGPath {
        let start = points[0]
        let end = points[points.count - 1]
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)

        let path = CGMutablePath()
        path.move(to: start)
        guard length > 0.5 else {
            path.addLine(to: end)
            return path
        }

        // Prefer the real mid sample so the arc tracks the finger; fall back to a slight bulge.
        // Keep bulge proportional so short (length-capped) slashes don't balloon visually.
        let midSample = points[points.count / 2]
        let chordMid = CGPoint(x: (start.x + end.x) * 0.5, y: (start.y + end.y) * 0.5)
        let maxBulge = length * 0.35
        let offsetX = midSample.x - chordMid.x
        let offsetY = midSample.y - chordMid.y
        let sampleOffset = hypot(offsetX, offsetY)
        let control: CGPoint
        if sampleOffset > 1 {
            let pull = min(sampleOffset * 2, maxBulge) / sampleOffset
            control = CGPoint(
                x: chordMid.x + offsetX * pull,
                y: chordMid.y + offsetY * pull
            )
        } else {
            let nx = -dy / length
            let ny = dx / length
            let bulge = min(length * 0.18, maxBulge)
            control = CGPoint(x: chordMid.x + nx * bulge, y: chordMid.y + ny * bulge)
        }
        path.addQuadCurve(to: end, control: control)
        return path
    }

    /// Layered blue glow + blade + white core (additive), Star Wars lightsaber style.
    func makeLightsaberSlashNode(path: CGPath) -> SKNode {
        let container = SKNode()
        container.zPosition = 50
        container.setScale(1)

        // Scale stroke to slash size so short capped trails don't read as full-screen blooms.
        let strokeScale = min(max(maxSlashPathLength / 80, 0.45), 1)

        let glow = makeGlowStroke(
            path: path,
            lineWidth: 14 * strokeScale,
            color: UIColor(red: 0.15, green: 0.45, blue: 1.0, alpha: 0.55),
            glowWidth: 18 * strokeScale
        )
        let blade = makeGlowStroke(
            path: path,
            lineWidth: 6 * strokeScale,
            color: UIColor(red: 0.35, green: 0.75, blue: 1.0, alpha: 0.95),
            glowWidth: 6 * strokeScale
        )
        let core = makeGlowStroke(
            path: path,
            lineWidth: 2.5 * strokeScale,
            color: UIColor.white.withAlphaComponent(0.95),
            glowWidth: 1 * strokeScale
        )
        glow.blendMode = .add
        blade.blendMode = .add
        core.blendMode = .add

        container.addChild(glow)
        container.addChild(blade)
        container.addChild(core)
        return container
    }
}
