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

        let textures = animation.frames.map(\.texture)
        let durations = animation.frames.map(\.duration)

        texture = textures[0]
        if let targetHeight {
            fitHeight(targetHeight)
        } else if size == .zero {
            size = textures[0].size()
        }

        applyScale(flipsHorizontally: animation.flipsHorizontally)

        let animAction: SKAction
        if let timePerFrame = Self.uniformFrameDuration(durations) {
            // Exact atlas timing when all frame weights are equal.
            animAction = .repeatForever(
                .animate(
                    with: textures,
                    timePerFrame: timePerFrame,
                    resize: false,
                    restore: false
                )
            )
        } else {
            let steps: [SKAction] = zip(textures, durations).flatMap { texture, duration in
                [
                    SKAction.setTexture(texture, resize: false),
                    SKAction.wait(forDuration: duration),
                ]
            }
            animAction = .repeatForever(.sequence(steps))
        }
        run(animAction, withKey: Self.animationActionKey)
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

    private static func uniformFrameDuration(_ durations: [TimeInterval]) -> TimeInterval? {
        guard let first = durations.first else { return nil }
        let uniform = durations.allSatisfy { abs($0 - first) < 0.000_001 }
        return uniform ? first : nil
    }
}
