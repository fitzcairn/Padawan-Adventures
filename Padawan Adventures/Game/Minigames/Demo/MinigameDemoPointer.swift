import SpriteKit
import UIKit

/// A `UITouch` whose location the demo driver moves between calls.
///
/// `point` is stored in **scene** coordinates. When SpriteKit asks for a view
/// location (so it can `convertPoint(fromView:)` into the scene), this converts
/// first — otherwise `touch.location(in: scene)` double-converts and Y-flips
/// under `aspectFit`, so choice hit-tests miss and dragged capacitors never move.
final class MinigameDemoTouch: UITouch {
    /// Point in scene coordinates. Converted to view space when an `SKView` asks.
    var point: CGPoint

    init(point: CGPoint) {
        self.point = point
        super.init()
    }

    override func location(in view: UIView?) -> CGPoint {
        viewCoordinates(in: view)
    }

    override func previousLocation(in view: UIView?) -> CGPoint {
        viewCoordinates(in: view)
    }

    private func viewCoordinates(in view: UIView?) -> CGPoint {
        if let skView = view as? SKView, let scene = skView.scene {
            return scene.convertPoint(toView: point)
        }
        // View-less unit tests: `location(in: SKNode)` typically passes this through.
        return point
    }
}

/// Feeds synthetic touches into a live scene so the demo exercises the real input path.
@MainActor
final class MinigameDemoPointer {
    private weak var scene: SKScene?
    private let cursor: MinigameDemoCursorNode
    private static let frameSeconds: TimeInterval = 1.0 / 60.0
    static let approachSeconds: TimeInterval = 0.35

    init(scene: SKScene, cursor: MinigameDemoCursorNode) {
        self.scene = scene
        self.cursor = cursor
    }

    func pause(_ seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }

    func tap(at point: CGPoint) async {
        guard let scene else { return }
        cursor.setPose(.pointer)
        await moveCursor(to: point, duration: Self.approachSeconds)
        let touch = MinigameDemoTouch(point: point)
        cursor.setPose(.tap)
        pressCursor(true)
        scene.touchesBegan(Set([touch]), with: nil)
        await pause(0.10)
        scene.touchesEnded(Set([touch]), with: nil)
        pressCursor(false)
        cursor.setPose(.pointer)
    }

    func drag(from: CGPoint, to: CGPoint, duration: TimeInterval) async {
        guard let scene else { return }
        cursor.setPose(.pointer)
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
        cursor.setPose(.pointer)
        await moveCursor(to: first, duration: Self.approachSeconds)
        let touch = MinigameDemoTouch(point: first)
        cursor.setPose(.swipe)
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
        cursor.setPose(.pointer)
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
        // `run(_:withKey:)` avoids the async `run(_:)` overload (preferred in
        // async contexts) which hangs when the scene has no update loop.
        cursor.run(move, withKey: "demoMove")
        await pause(duration)
        cursor.position = point
    }

    private func pressCursor(_ down: Bool) {
        cursor.setPressed(down)
    }
}

enum MinigameDemoCursor {
    /// Above `SceneLayer.player` (1_000) so it is never occluded.
    static let zPosition: CGFloat = 5_000

    /// Circle used when baked hand art is unavailable (tests / missing assets).
    @MainActor
    static func makeFallbackCircle(diameter: CGFloat) -> SKNode {
        let node = SKShapeNode(circleOfRadius: diameter * 0.5)
        node.fillColor = UIColor.white.withAlphaComponent(0.28)
        node.strokeColor = UIColor.white.withAlphaComponent(0.85)
        node.lineWidth = 3
        node.zPosition = 0
        node.name = "demoCursorFallback"
        return node
    }
}

/// The virtual finger. Uses baked hand art when available, else the old circle.
@MainActor
final class MinigameDemoCursorNode: SKNode {
    private let art: [MinigameTutorialCursorSprites.Pose: MinigameTutorialCursorSprites.Art]?
    private let sprite: SKSpriteNode?

    /// `side` is the square the (square) source frame is fitted into.
    init(side: CGFloat) {
        let loaded = MinigameTutorialCursorSprites.load()
        art = loaded
        if let loaded {
            let node = SKSpriteNode(color: .clear, size: CGSize(width: side, height: side))
            sprite = node
            super.init()
            node.position = .zero
            addChild(node)
            setPose(.pointer)
        } else {
            sprite = nil
            super.init()
            addChild(MinigameDemoCursor.makeFallbackCircle(diameter: side * 0.3))
        }
        zPosition = MinigameDemoCursor.zPosition
        name = "demoCursor"
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setPose(_ pose: MinigameTutorialCursorSprites.Pose) {
        guard let sprite, let entry = art?[pose] else { return }
        sprite.texture = entry.texture
        sprite.anchorPoint = entry.anchor
    }

    func setPressed(_ down: Bool) {
        run(.scale(to: down ? 0.85 : 1.0, duration: 0.08), withKey: "press")
    }
}
