import UIKit

enum AppOrientation {
    /// Landscape in either direction; portrait is not supported.
    static let mask: UIInterfaceOrientationMask = [.landscapeLeft, .landscapeRight]
}

/// Shared orientation policy for every screen in the app.
class LandscapeHostingController: UIViewController {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        AppOrientation.mask
    }

    override var prefersStatusBarHidden: Bool { true }
}

/// Navigation controller that forwards landscape-left/right support from its top VC.
final class LandscapeNavigationController: UINavigationController {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        topViewController?.supportedInterfaceOrientations ?? AppOrientation.mask
    }

    override var prefersStatusBarHidden: Bool {
        topViewController?.prefersStatusBarHidden ?? true
    }
}
