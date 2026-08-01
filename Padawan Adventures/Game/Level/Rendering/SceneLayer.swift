import CoreGraphics

/// Shared SpriteKit z-order bands for minigame scenes.
enum SceneLayer {
    static let background: CGFloat = 0
    static let pads: CGFloat = 1
    static let placedTiles: CGFloat = 5
    static let slotBox: CGFloat = 8
    static let letterPlatform: CGFloat = 10
    static let endpoint: CGFloat = 8
    static let trayTiles: CGFloat = 10
    static let dragged: CGFloat = 60
    static let overlay: CGFloat = 50
    /// Above pads and letter platforms when sibling order sums parent z.
    static let player: CGFloat = 1_000

    /// Local z within a multi-label stack (outline → shadow → fill).
    enum LabelStack {
        static let outline: CGFloat = 0
        static let innerShadow: CGFloat = 1
        static let fill: CGFloat = 2
    }
}
