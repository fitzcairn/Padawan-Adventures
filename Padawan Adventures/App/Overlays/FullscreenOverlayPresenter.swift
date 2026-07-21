import UIKit

/// Presents fullscreen overlays/minigames with shared re-entrancy, optional world fade-out,
/// content fade-out on dismiss, and a single resolve completion path.
@MainActor
final class FullscreenOverlayPresenter {
    struct Dependencies {
        var fadeWorldOut: (_ completion: @escaping () -> Void) -> Void
        var present: (UIViewController) -> Void
        var dismiss: (_ viewController: UIViewController, _ completion: @escaping () -> Void) -> Void
    }

    private var isPresenting = false
    private let dependencies: Dependencies

    var isBusy: Bool { isPresenting }

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    /// Production convenience: present from `host`, fade the SpriteKit world via `fadeWorldOut`.
    convenience init(
        host: UIViewController,
        fadeWorldOut: @escaping (_ completion: @escaping () -> Void) -> Void
    ) {
        weak let weakHost = host
        self.init(dependencies: Dependencies(
            fadeWorldOut: fadeWorldOut,
            present: { viewController in
                viewController.modalPresentationStyle = .fullScreen
                weakHost?.present(viewController, animated: false)
            },
            dismiss: { viewController, completion in
                let dismissHost = {
                    viewController.dismiss(animated: false, completion: completion)
                }
                if let overlay = viewController as? FullscreenOverlayController {
                    overlay.fadeOutContent(completion: dismissHost)
                } else {
                    dismissHost()
                }
            }
        ))
    }

    /// - Parameters:
    ///   - fadeWorldOut: When true, runs the world fade before presenting.
    ///   - makeViewController: Builds the overlay/minigame VC.
    ///   - onResolved: Called after dismiss; invoke `done` when resolve work finishes so the presenter unlocks.
    func present(
        fadeWorldOut: Bool = true,
        makeViewController: @escaping () -> FullscreenOverlayController,
        onResolved: @escaping (_ done: @escaping () -> Void) -> Void
    ) {
        guard !isPresenting else { return }
        isPresenting = true

        let show = { [weak self] in
            guard let self else { return }
            let viewController = makeViewController()
            viewController.onFinished = { [weak self, weak viewController] in
                guard let self, let viewController else { return }
                viewController.onFinished = nil
                self.dependencies.dismiss(viewController) {
                    onResolved {
                        self.isPresenting = false
                    }
                }
            }
            self.dependencies.present(viewController)
        }

        if fadeWorldOut {
            dependencies.fadeWorldOut(show)
        } else {
            show()
        }
    }
}
