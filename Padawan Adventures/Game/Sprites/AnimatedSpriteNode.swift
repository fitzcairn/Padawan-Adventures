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
    /// Points per texture pixel, locked from the first fitted clip so idle/walk/
    /// facing changes keep a stable character scale when trimmed sheet heights differ.
    private var lockedPixelsToPoints: CGFloat?
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

    /// Locks height from the current texture and freezes pixels-to-points for later clips.
    func fitHeight(_ height: CGFloat) {
        targetHeight = height
        targetWidth = nil
        applyTargetSizing(resetLock: true)
    }

    /// Locks width from the current texture and freezes pixels-to-points for later clips.
    func fitWidth(_ width: CGFloat) {
        targetWidth = width
        targetHeight = nil
        applyTargetSizing(resetLock: true)
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

    /// Shows frame 0 of `name` with correct scale/anchor; does not start a looping action.
    @MainActor
    func show(name: String, library: SpriteLibrary, libraryID: String = "player") {
        guard let animation = library.animation(id: libraryID, named: name),
              !animation.frames.isEmpty else {
            return
        }
        preparePlayback(animation: animation, name: name)
        // Freeze on the first frame (no forever / one-shot action).
        removeAction(forKey: Self.animationActionKey)
        currentAnimationName = nil
    }

    /// Plays a concrete animation (e.g. item/enemy clips supplied directly).
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

    /// Plays `name` once from frame 0, then restores frame 0. Always restarts if already playing.
    @MainActor
    func playOnce(name: String, library: SpriteLibrary, libraryID: String = "player") {
        guard let animation = library.animation(id: libraryID, named: name),
              !animation.frames.isEmpty else {
            return
        }
        preparePlayback(animation: animation, name: name)
        guard animation.frames.count > 1 else {
            currentAnimationName = nil
            return
        }
        let onceAction = Self.makeOnceAction(for: animation)
        let firstTexture = animation.frames[0].texture
        run(
            .sequence([
                onceAction,
                .run { [weak self] in
                    guard let self else { return }
                    self.texture = firstTexture
                    self.currentAnimationName = nil
                },
            ]),
            withKey: Self.animationActionKey
        )
    }

    /// Plays `name` from frame 0 a fixed number of times, then calls `completion`. Always restarts.
    @MainActor
    func play(
        name: String,
        library: SpriteLibrary,
        libraryID: String = "player",
        count: Int,
        completion: (() -> Void)? = nil
    ) {
        guard count > 0,
              let animation = library.animation(id: libraryID, named: name),
              !animation.frames.isEmpty else {
            completion?()
            return
        }
        preparePlayback(animation: animation, name: name)
        guard animation.frames.count > 1 else {
            currentAnimationName = nil
            completion?()
            return
        }
        let once = Self.makeOnceAction(for: animation)
        let body: SKAction = count == 1 ? once : .repeat(once, count: count)
        run(
            .sequence([
                body,
                .run { [weak self] in
                    self?.currentAnimationName = nil
                    completion?()
                },
            ]),
            withKey: Self.animationActionKey
        )
    }

    /// Builds a forever-looping texture animation action (uncached; used by floors and cache fill).
    static func makeLoopingAction(for animation: SpriteAnimation) -> SKAction {
        .repeatForever(makeOnceAction(for: animation))
    }

    /// Builds a single-pass texture animation action (no loop).
    static func makeOnceAction(for animation: SpriteAnimation) -> SKAction {
        let textures = animation.frames.map(\.texture)
        let durations = animation.frames.map(\.duration)
        if let timePerFrame = uniformFrameDuration(durations) {
            return .animate(
                with: textures,
                timePerFrame: timePerFrame,
                resize: false,
                restore: false
            )
        }
        let steps: [SKAction] = zip(textures, durations).flatMap { texture, duration in
            [
                SKAction.setTexture(texture, resize: false),
                SKAction.wait(forDuration: duration),
            ]
        }
        return .sequence(steps)
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
        if targetWidth != nil || targetHeight != nil {
            // Keep the first-fitted pixels-to-points so walk/facing sheets that
            // trim taller/shorter than idle do not rescale the character.
            applyTargetSizing(resetLock: false)
        } else if size == .zero {
            size = textures[0].size()
        }

        applyScale(flipsHorizontally: animation.flipsHorizontally)
    }

    /// Sizes the node from `targetHeight` / `targetWidth`, optionally establishing
    /// a locked pixels-to-points scale used by later animation swaps.
    private func applyTargetSizing(resetLock: Bool) {
        if resetLock {
            lockedPixelsToPoints = nil
        }

        guard let texture else {
            if let targetHeight {
                size = CGSize(width: targetHeight, height: targetHeight)
            } else if let targetWidth {
                size = CGSize(width: targetWidth, height: targetWidth)
            }
            return
        }

        let texSize = texture.size()
        guard texSize.width > 0, texSize.height > 0 else {
            if let targetHeight {
                size = CGSize(width: targetHeight, height: targetHeight)
            } else if let targetWidth {
                size = CGSize(width: targetWidth, height: targetWidth)
            }
            return
        }

        if let locked = lockedPixelsToPoints {
            size = CGSize(width: texSize.width * locked, height: texSize.height * locked)
            return
        }

        if let targetHeight {
            let pixelsToPoints = targetHeight / texSize.height
            lockedPixelsToPoints = pixelsToPoints
            size = CGSize(width: texSize.width * pixelsToPoints, height: targetHeight)
            return
        }

        if let targetWidth {
            let pixelsToPoints = targetWidth / texSize.width
            lockedPixelsToPoints = pixelsToPoints
            size = CGSize(width: targetWidth, height: texSize.height * pixelsToPoints)
        }
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
