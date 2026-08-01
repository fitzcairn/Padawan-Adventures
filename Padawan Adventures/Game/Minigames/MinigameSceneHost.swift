import SpriteKit

/// Owns the scene-creation and resize lifecycle shared by every minigame.
///
/// Deliberately not an `ObservableObject`: each session controller keeps its own
/// `@Published scene` and is notified through `onReady`, so no `@Published`
/// inheritance is involved.
@MainActor
final class MinigameSceneHost<Scene: SKScene> {
    /// Smallest scene SpriteKit is allowed to lay out against.
    static var minimumSize: CGSize { CGSize(width: 320, height: 240) }
    /// Ignore sub-pixel jitter from SwiftUI layout passes.
    private static var resizeThreshold: CGFloat { 8 }

    private let prepare: (() async -> Void)?
    private let make: (CGSize) -> Scene
    private let onReady: (Scene) -> Void

    private var scene: Scene?
    private var isCreating = false
    private var pendingSize: CGSize?

    init(
        prepare: (() async -> Void)? = nil,
        make: @escaping (CGSize) -> Scene,
        onReady: @escaping (Scene) -> Void
    ) {
        self.prepare = prepare
        self.make = make
        self.onReady = onReady
    }

    static func sanitized(_ size: CGSize) -> CGSize {
        CGSize(
            width: max(size.width, minimumSize.width),
            height: max(size.height, minimumSize.height)
        )
    }

    func ensureScene(size: CGSize) {
        let safe = Self.sanitized(size)
        if scene != nil {
            updateSceneSizeIfNeeded(safe)
            return
        }
        pendingSize = safe
        guard !isCreating else { return }
        isCreating = true

        Task { @MainActor in
            await prepare?()
            let created = make(pendingSize ?? safe)
            scene = created
            isCreating = false
            onReady(created)
        }
    }

    func updateSceneSizeIfNeeded(_ size: CGSize) {
        let safe = Self.sanitized(size)
        guard let scene else {
            pendingSize = safe
            return
        }
        let dw = abs(scene.size.width - safe.width)
        let dh = abs(scene.size.height - safe.height)
        guard dw > Self.resizeThreshold || dh > Self.resizeThreshold else { return }
        scene.size = safe
    }
}
