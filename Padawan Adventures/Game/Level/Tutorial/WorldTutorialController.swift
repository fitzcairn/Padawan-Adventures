import SpriteKit
import UIKit

/// Owns the hand cursor, "Tap to continue" hint, and async choreography for the
/// level-1 world tutorial. Cancelled by a real touch or when the host disappears.
@MainActor
final class WorldTutorialController: WorldTutorialStaging {
    private weak var scene: GameScene?
    private let onFinished: () -> Void
    private var cursor: MinigameDemoCursorNode?
    private var hint: SKLabelNode?
    private var pointer: MinigameDemoPointer?
    private var task: Task<Void, Never>?
    private var didFinish = false
    private(set) var demoTarget: GridCoord?

    init(scene: GameScene, onFinished: @escaping () -> Void) {
        self.scene = scene
        self.onFinished = onFinished
        self.demoTarget = WorldTutorialTargetPicker.demoTarget(in: scene.currentWorld)
    }

    func start() {
        guard let scene, !didFinish else { return }
        scene.worldTutorial = self

        let side = min(scene.size.width, scene.size.height) * 0.24
        let cursor = MinigameDemoCursorNode(side: side)
        cursor.zPosition = IsometricMath.occlusionBandBase * 2
        cursor.alpha = 0
        scene.addChild(cursor)
        self.cursor = cursor

        let hint = TutorialHintStyle.makeLabel(text: Strings.text("world_tutorial_tap_to_continue"))
        hint.name = "worldTutorialHint"
        hint.zPosition = IsometricMath.occlusionBandBase * 2
        hint.alpha = 0
        if let view = scene.view {
            let bottomInset = view.safeAreaInsets.bottom
            hint.position = scene.convertPoint(fromView: CGPoint(
                x: view.bounds.midX,
                y: view.bounds.maxY - bottomInset - 12
            ))
        } else {
            hint.position = CGPoint(x: 0, y: -scene.size.height * 0.5 + 24)
        }
        scene.addChild(hint)
        self.hint = hint

        let pointer = MinigameDemoPointer(scene: scene, cursor: cursor)
        self.pointer = pointer

        let script = WorldTutorialScript(staging: self, performer: pointer)
        task = Task { [weak self] in
            await script.run()
            self?.finish()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        finish()
    }

    // MARK: - WorldTutorialStaging

    var spawnCoord: GridCoord {
        scene?.currentWorld.spawn ?? GridCoord(x: 0, y: 0, story: 0)
    }

    var isPlayerMoving: Bool {
        scene?.isPlayerMoving ?? false
    }

    var isInterrupted: Bool {
        guard let scene else { return true }
        return scene.isPausedForEncounter || scene.isResolvingPickup
    }

    func scenePoint(for coord: GridCoord) -> CGPoint {
        guard let scene else { return .zero }
        return IsometricMath.viewPosition(
            worldPoint: IsometricMath.entityScreenPosition(coord, config: scene.isoConfig),
            focus: scene.viewportFocus,
            viewCenter: scene.renderer.sceneViewCenter
        )
    }

    func scenePoint(atViewFraction fraction: CGPoint) -> CGPoint {
        guard let scene, let view = scene.view else { return .zero }
        return scene.convertPoint(fromView: CGPoint(
            x: view.bounds.width * fraction.x,
            y: view.bounds.height * fraction.y
        ))
    }

    func showTutorialChrome(cursorAt point: CGPoint, fadeSeconds: TimeInterval) async {
        cursor?.position = point
        cursor?.removeAllActions()
        hint?.removeAllActions()
        cursor?.run(.fadeIn(withDuration: fadeSeconds), withKey: "tutorialFade")
        hint?.run(.fadeIn(withDuration: fadeSeconds), withKey: "tutorialFade")
        try? await Task.sleep(nanoseconds: UInt64(max(0, fadeSeconds) * 1_000_000_000))
        cursor?.alpha = 1
        hint?.alpha = 1
    }

    func hideTutorialChrome(fadeSeconds: TimeInterval) async {
        cursor?.removeAllActions()
        hint?.removeAllActions()
        cursor?.run(.fadeOut(withDuration: fadeSeconds), withKey: "tutorialFade")
        hint?.run(.fadeOut(withDuration: fadeSeconds), withKey: "tutorialFade")
        try? await Task.sleep(nanoseconds: UInt64(max(0, fadeSeconds) * 1_000_000_000))
        cursor?.alpha = 0
        hint?.alpha = 0
    }

    func speakIntro() {
        Strings.speak("world_tutorial_intro")
    }

    func beginCameraOwnership() {
        scene?.tutorialOwnsCamera = true
    }

    func endCameraOwnership() {
        scene?.tutorialOwnsCamera = false
    }

    func glideCameraToPlayer(duration: TimeInterval) async {
        guard let scene else { return }
        let start = scene.viewportFocus
        let playerCoord = scene.currentWorld.playerPosition ?? scene.currentWorld.spawn
        let end = IsometricMath.entityScreenPosition(playerCoord, config: scene.isoConfig)
        let frameSeconds: TimeInterval = 1.0 / 60.0
        let steps = max(2, Int(duration / frameSeconds))
        for step in 1...steps {
            if Task.isCancelled { return }
            let raw = CGFloat(step) / CGFloat(steps)
            let t = raw * raw * (3 - 2 * raw)
            scene.setViewportFocus(CGPoint(
                x: start.x + (end.x - start.x) * t,
                y: start.y + (end.y - start.y) * t
            ))
            try? await Task.sleep(nanoseconds: UInt64(frameSeconds * 1_000_000_000))
        }
        scene.setViewportFocus(end)
    }

    // MARK: - Private

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        task?.cancel()
        task = nil
        // The intro line outlives a tutorial the player taps through, so fade it.
        SoundEffectsController.shared.fadeOutVoiceOver()
        cursor?.removeAllActions()
        hint?.removeAllActions()
        cursor?.removeFromParent()
        hint?.removeFromParent()
        cursor = nil
        hint = nil
        pointer = nil
        scene?.finishWorldTutorial()
        onFinished()
    }
}
