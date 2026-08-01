import SpriteKit

/// Base class for minigame SKScenes with shared lifecycle and layout guards.
class MinigameScene: SKScene {
    var didSetup = false
    var isBuilding = false
    var didEnd = false

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .aspectFit
        backgroundColor = .black
        anchorPoint = .zero
        isUserInteractionEnabled = true
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        guard !didSetup else { return }
        isBuilding = true
        defer {
            isBuilding = false
            didSetup = true
        }
        buildContent()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard didSetup, !isBuilding, !didEnd else { return }
        guard size.width > 1, size.height > 1 else { return }
        guard oldSize != size else { return }
        rebuildLayout()
    }

    /// Called once on first `didMove`; `didSetup` is set only after this returns.
    func buildContent() {}

    /// Called on meaningful size changes after the initial build.
    func rebuildLayout() {}
}
