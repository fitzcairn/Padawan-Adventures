import SpriteKit

/// Screen-agnostic looping sprite player backed by a `SpriteLibrary` animation.
final class AnimatedSpriteNode: SKSpriteNode {
    static let animationActionKey = "animatedSprite"
    static let nodeName = "animatedSprite"

    private(set) var currentAnimationName: String?
    private var baseScale: CGFloat = 1
    /// When set, height is locked and width follows the texture aspect ratio.
    var targetHeight: CGFloat?
    /// When set, width is locked and height follows the texture aspect ratio.
    var targetWidth: CGFloat?
    /// When true (default), applies `yScale = -1` to correct UIImage→SKTexture V-inversion.
    /// Floor tiles sit under an isometric diamond and need `false` so content stays below the origin.
    var correctsUIImageVInversion = true

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
        targetWidth = nil
        guard let texture, texture.size().height > 0 else {
            size = CGSize(width: height, height: height)
            return
        }
        let aspect = texture.size().width / texture.size().height
        size = CGSize(width: height * aspect, height: height)
    }

    /// Locks width and sets height from the current texture's aspect ratio.
    func fitWidth(_ width: CGFloat) {
        targetWidth = width
        targetHeight = nil
        guard let texture, texture.size().width > 0 else {
            size = CGSize(width: width, height: width)
            return
        }
        let aspect = texture.size().height / texture.size().width
        size = CGSize(width: width, height: width * aspect)
    }

    /// Plays `name` from `library` if present. No-ops when already playing the same clip.
    @MainActor
    func play(name: String, library: SpriteLibrary, libraryID: String = "player") {
        guard currentAnimationName != name else { return }
        guard let animation = library.animation(id: libraryID, named: name),
              !animation.frames.isEmpty else {
            return
        }
        preparePlayback(animation: animation, name: name)
        // Static one-frame clips keep the texture without a looping action.
        guard animation.frames.count > 1 else { return }
        if let animAction = library.action(id: libraryID, named: name) {
            run(animAction, withKey: Self.animationActionKey)
        }
    }

    /// Plays a concrete animation (e.g. floor terrains from `FloorSpriteLibrary`).
    func play(animation: SpriteAnimation, name: String? = nil) {
        let key = name ?? currentAnimationName ?? "animation"
        if let name, currentAnimationName == name, action(forKey: Self.animationActionKey) != nil {
            return
        }
        guard !animation.frames.isEmpty else { return }

        preparePlayback(animation: animation, name: key)

        // Static one-frame clips (floors) keep the texture without a looping action.
        guard animation.frames.count > 1 else { return }

        run(Self.makeLoopingAction(for: animation), withKey: Self.animationActionKey)
    }

    /// Builds a forever-looping texture animation action (uncached; used by floors and cache fill).
    static func makeLoopingAction(for animation: SpriteAnimation) -> SKAction {
        let textures = animation.frames.map(\.texture)
        let durations = animation.frames.map(\.duration)
        if let timePerFrame = uniformFrameDuration(durations) {
            // Exact atlas timing when all frame weights are equal.
            return .repeatForever(
                .animate(
                    with: textures,
                    timePerFrame: timePerFrame,
                    resize: false,
                    restore: false
                )
            )
        }
        let steps: [SKAction] = zip(textures, durations).flatMap { texture, duration in
            [
                SKAction.setTexture(texture, resize: false),
                SKAction.wait(forDuration: duration),
            ]
        }
        return .repeatForever(.sequence(steps))
    }

    /// Uniform display scale (absolute); horizontal flip is reapplied from the active clip.
    func setDisplayScale(_ scale: CGFloat) {
        baseScale = abs(scale)
        applyScale(flipsHorizontally: xScale < 0)
    }

    private func preparePlayback(animation: SpriteAnimation, name: String) {
        currentAnimationName = name
        removeAction(forKey: Self.animationActionKey)

        let textures = animation.frames.map(\.texture)
        texture = textures[0]
        if let targetWidth {
            fitWidth(targetWidth)
        } else if let targetHeight {
            fitHeight(targetHeight)
        } else if size == .zero {
            size = textures[0].size()
        }

        applyScale(flipsHorizontally: animation.flipsHorizontally)
    }

    private func applyScale(flipsHorizontally: Bool) {
        // Left/right mirror for flip_of animations (NW/SW from NE/SE, etc.).
        let flipX: CGFloat = flipsHorizontally ? -1 : 1
        xScale = baseScale * flipX
        // Correct UIImage/SKTexture V-inversion when requested; feet stay on tile via anchor y = 1.
        yScale = correctsUIImageVInversion ? -baseScale : baseScale
    }

    private static func uniformFrameDuration(_ durations: [TimeInterval]) -> TimeInterval? {
        guard let first = durations.first else { return nil }
        let uniform = durations.allSatisfy { abs($0 - first) < 0.000_001 }
        return uniform ? first : nil
    }
}
