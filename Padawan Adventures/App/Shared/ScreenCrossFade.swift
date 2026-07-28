import UIKit

/// Shared visual cross-fade used for all app and game screen changes.
enum ScreenCrossFade {
    static let duration: TimeInterval = 0.3
}

extension AppWindow {
    /// Cross-dissolves to a new root view controller (flow ↔ gameplay).
    @MainActor
    static func setRoot(
        _ viewController: UIViewController,
        in window: UIWindow? = nil,
        duration: TimeInterval = ScreenCrossFade.duration,
        completion: (() -> Void)? = nil
    ) {
        guard let window = window ?? key else {
            completion?()
            return
        }

        window.makeKeyAndVisible()
        UIView.transition(
            with: window,
            duration: duration,
            options: [.transitionCrossDissolve, .allowAnimatedContent],
            animations: {
                window.rootViewController = viewController
            },
            completion: { _ in
                completion?()
            }
        )
    }
}
