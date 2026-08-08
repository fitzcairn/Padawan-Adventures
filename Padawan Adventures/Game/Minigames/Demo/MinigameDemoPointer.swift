import SpriteKit
import UIKit

/// A `UITouch` whose location the demo driver moves between calls.
final class MinigameDemoTouch: UITouch {
    var point: CGPoint

    init(point: CGPoint) {
        self.point = point
        super.init()
    }

    override func location(in view: UIView?) -> CGPoint { point }
    override func previousLocation(in view: UIView?) -> CGPoint { point }
}

/// Feeds synthetic touches into a live scene so the demo exercises the real input path.
@MainActor
final class MinigameDemoPointer {
    private weak var scene: SKScene?
    private let cursor: SKNode
    private static let frameSeconds: TimeInterval = 1.0 / 60.0
    private static let approachSeconds: TimeInterval = 0.35

    init(scene: SKScene, cursor: SKNode) {
        self.scene = scene
        self.cursor = cursor
    }

    func pause(_ seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }

    func tap(at point: CGPoint) async {
        guard let scene else { return }
        await moveCursor(to: point, duration: Self.approachSeconds)
        let touch = MinigameDemoTouch(point: point)
        pressCursor(true)
        scene.touchesBegan(Set([touch]), with: nil)
        await pause(0.10)
        scene.touchesEnded(Set([touch]), with: nil)
        pressCursor(false)
    }

    func drag(from: CGPoint, to: CGPoint, duration: TimeInterval) async {
        guard let scene else { return }
        await moveCursor(to: from, duration: Self.approachSeconds)
        let touch = MinigameDemoTouch(point: from)
        pressCursor(true)
        scene.touchesBegan(Set([touch]), with: nil)
        await interpolate(touch: touch, from: from, to: to, duration: duration) {
            scene.touchesMoved(Set([touch]), with: nil)
        }
        scene.touchesEnded(Set([touch]), with: nil)
        pressCursor(false)
    }

    /// Combat slash. Must finish inside `CombatScene.slashMaxSeconds` (0.5s default)
    /// or `hasSlashTimedOut` ends the stroke early.
    func swipe(_ points: [CGPoint], duration: TimeInterval) async {
        guard let scene, let first = points.first, points.count >= 2 else { return }
        await moveCursor(to: first, duration: Self.approachSeconds)
        let touch = MinigameDemoTouch(point: first)
        pressCursor(true)
        scene.touchesBegan(Set([touch]), with: nil)
        let legSeconds = duration / TimeInterval(points.count - 1)
        for index in 1..<points.count {
            await interpolate(
                touch: touch,
                from: points[index - 1],
                to: points[index],
                duration: legSeconds,
                eased: false
            ) { scene.touchesMoved(Set([touch]), with: nil) }
        }
        scene.touchesEnded(Set([touch]), with: nil)
        pressCursor(false)
    }

    // MARK: - Private

    private func interpolate(
        touch: MinigameDemoTouch,
        from: CGPoint,
        to: CGPoint,
        duration: TimeInterval,
        eased: Bool = true,
        emit: () -> Void
    ) async {
        let steps = max(2, Int(duration / Self.frameSeconds))
        for step in 1...steps {
            if Task.isCancelled { return }
            let raw = CGFloat(step) / CGFloat(steps)
            let t = eased ? raw * raw * (3 - 2 * raw) : raw
            touch.point = CGPoint(
                x: from.x + (to.x - from.x) * t,
                y: from.y + (to.y - from.y) * t
            )
            cursor.position = touch.point
            emit()
            await pause(Self.frameSeconds)
        }
    }

    private func moveCursor(to point: CGPoint, duration: TimeInterval) async {
        cursor.removeAllActions()
        let move = SKAction.move(to: point, duration: duration)
        move.timingMode = .easeInEaseOut
        await cursor.run(move)
        await pause(duration)
        cursor.position = point
    }

    private func pressCursor(_ down: Bool) {
        cursor.run(.scale(to: down ? 0.8 : 1.0, duration: 0.08))
    }
}

enum MinigameDemoCursor {
    /// Above `SceneLayer.player` (1_000) so it is never occluded.
    static let zPosition: CGFloat = 5_000

    @MainActor
    static func make(diameter: CGFloat) -> SKNode {
        let node = SKShapeNode(circleOfRadius: diameter * 0.5)
        node.fillColor = UIColor.white.withAlphaComponent(0.28)
        node.strokeColor = UIColor.white.withAlphaComponent(0.85)
        node.lineWidth = 3
        node.zPosition = zPosition
        node.name = "demoCursor"
        return node
    }
}
