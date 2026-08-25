import SpriteKit

struct SpriteFrame {
    var texture: SKTexture
    var duration: TimeInterval
}

struct SpriteAnimation {
    var frames: [SpriteFrame]
    var flipsHorizontally: Bool

    init(frames: [SpriteFrame], flipsHorizontally: Bool = false) {
        self.frames = frames
        self.flipsHorizontally = flipsHorizontally
    }

    func flipped() -> SpriteAnimation {
        SpriteAnimation(frames: frames, flipsHorizontally: true)
    }

    /// Inclusive frame slice; out-of-range bounds clamp to the clip.
    func slice(_ range: ClosedRange<Int>, frameDuration: TimeInterval? = nil) -> SpriteAnimation {
        guard !frames.isEmpty else { return self }
        let last = frames.count - 1
        let lo = min(max(range.lowerBound, 0), last)
        let hi = min(max(range.upperBound, lo), last)
        let sliced = frames[lo...hi].map { frame in
            SpriteFrame(texture: frame.texture, duration: frameDuration ?? frame.duration)
        }
        return SpriteAnimation(frames: Array(sliced), flipsHorizontally: flipsHorizontally)
    }
}
