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
}
