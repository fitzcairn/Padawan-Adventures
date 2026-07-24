import SpriteKit

/// Screen-agnostic looping sprite player backed by a `SpriteLibrary` animation.
final class AnimatedSpriteNode: SKSpriteNode {
    static let animationActionKey = "animatedSprite"
    static let nodeName = "animatedSprite"

    private(set) var currentAnimationName: String?
    private var baseScale: CGFloat = 1
    /// When set, height is locked and width follows the texture aspect ratio.
    var targetHeight: CGFloat?

    convenience init(size: CGSize) {
        self.init(texture: nil, color: .clear, size: size)
        name = Self.nodeName
        // UIImage→SKTexture is V-inverted; we correct with negative yScale.
        // Anchor at texture-top (1) so after that Y flip the *visual* bottom
        // (feet) stays on the node position / tile center.
        anchorPoint = CGPoint(x: 0.5, y: 1)
    }

    /// Locks height and sets width from the current texture's aspect ratio.
    func fitHeight(_ height: CGFloat) {
        targetHeight = height
        guard let texture, texture.size().height > 0 else {
            size = CGSize(width: height, height: height)
            return
        }
        let aspect = texture.size().width / texture.size().height
        size = CGSize(width: height * aspect, height: height)
    }

    /// Plays `name` from `library` if present. No-ops when already playing the same clip.
    @MainActor
    func play(name: String, library: SpriteLibrary, libraryID: String = "player") {
        guard currentAnimationName != name else { return }
        guard let animation = library.animation(id: libraryID, named: name),
              !animation.frames.isEmpty else {
            return
        }

        currentAnimationName = name
        removeAction(forKey: Self.animationActionKey)

        let first = animation.frames[0].texture
        SpriteSheetLoader.prepareTextureForScaledDisplay(first)
        texture = first
        if let targetHeight {
            fitHeight(targetHeight)
        } else if size == .zero {
            size = first.size()
        }

        applyScale(flipsHorizontally: animation.flipsHorizontally)

        let actions: [SKAction] = animation.frames.flatMap { frame in
            [
                SKAction.run { [weak self] in
                    SpriteSheetLoader.prepareTextureForScaledDisplay(frame.texture)
                    self?.texture = frame.texture
                },
                SKAction.wait(forDuration: frame.duration),
            ]
        }
        run(.repeatForever(.sequence(actions)), withKey: Self.animationActionKey)
    }

    /// Uniform display scale (absolute); horizontal flip is reapplied from the active clip.
    func setDisplayScale(_ scale: CGFloat) {
        baseScale = abs(scale)
        applyScale(flipsHorizontally: xScale < 0)
    }

    private func applyScale(flipsHorizontally: Bool) {
        // Left/right mirror for flip_of animations (NW/SW from NE/SE, etc.).
        let flipX: CGFloat = flipsHorizontally ? -1 : 1
        xScale = baseScale * flipX
        // Correct UIImage/SKTexture V-inversion; feet stay on tile via anchor y = 1.
        yScale = -baseScale
    }
}
