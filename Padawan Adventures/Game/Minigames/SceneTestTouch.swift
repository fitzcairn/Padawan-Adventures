import UIKit

/// Synthetic touch used by scene unit tests that drive `touchesBegan`/`touchesMoved`
/// without a real `UIView` hit-test loop.
final class SceneTestTouch: UITouch {
    let location: CGPoint

    init(location: CGPoint) {
        self.location = location
        super.init()
    }

    override func location(in view: UIView?) -> CGPoint {
        location
    }
}
