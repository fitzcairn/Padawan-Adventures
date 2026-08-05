import UIKit

/// How an overlay returns control to the game world after `finish()`.
///
/// Prepare world state before calling either method (the cover is still up). Then:
/// - `crossfadeToWorld` fades the host out while the world fades in (victory / retreat)
/// - `dismissWhileCovered` removes the host without revealing the world (chain to defeat)
@MainActor
struct OverlayReturn {
    enum Style {
        case crossfadeToWorld
        case dismissWhileCovered
    }

    fileprivate let perform: (Style, @escaping (_ done: @escaping () -> Void) -> Void) -> Void

    /// Crossfade overlay → world, then run `after` (call `done` when post-reveal work finishes).
    func crossfadeToWorld(_ after: @escaping (_ done: @escaping () -> Void) -> Void) {
        perform(.crossfadeToWorld, after)
    }

    /// Dismiss while the world stays faded, then run `after` (call `done` when finished).
    func dismissWhileCovered(_ after: @escaping (_ done: @escaping () -> Void) -> Void) {
        perform(.dismissWhileCovered, after)
    }
}

/// Presents fullscreen overlays/minigames with shared re-entrancy, optional world fade-out,
/// centralized return-to-world crossfade, and a single resolve completion path.
@MainActor
final class FullscreenOverlayPresenter {
    struct Dependencies {
        var fadeWorldOut: (_ duration: TimeInterval, _ completion: @escaping () -> Void) -> Void
        var fadeWorldIn: (_ duration: TimeInterval, _ completion: @escaping () -> Void) -> Void
        var present: (UIViewController) -> Void
        var dismiss: (_ viewController: UIViewController, _ completion: @escaping () -> Void) -> Void
    }

    /// Duration for overlay↔world fades (`WorldFade.duration`).
    static var worldCrossfadeDuration: TimeInterval { WorldFade.duration }

    private var isPresenting = false
    private let dependencies: Dependencies

    var isBusy: Bool { isPresenting }

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    /// Production convenience: present from `host`, fade the SpriteKit world via the given hooks.
    convenience init(
        host: UIViewController,
        fadeWorldOut: @escaping (_ duration: TimeInterval, _ completion: @escaping () -> Void) -> Void,
        fadeWorldIn: @escaping (_ duration: TimeInterval, _ completion: @escaping () -> Void) -> Void
    ) {
        weak let weakHost = host
        self.init(dependencies: Dependencies(
            fadeWorldOut: fadeWorldOut,
            fadeWorldIn: fadeWorldIn,
            present: { viewController in
                // overFullScreen keeps the game world in the hierarchy so overlay→world
                // crossfades can reveal it underneath as the host fades out.
                viewController.modalPresentationStyle = .overFullScreen
                weakHost?.present(viewController, animated: false)
            },
            dismiss: { viewController, completion in
                viewController.dismiss(animated: false, completion: completion)
            }
        ))
    }

    /// - Parameters:
    ///   - fadeWorldOut: When true, fades the world before presenting; return uses `OverlayReturn`.
    ///   - makeViewController: Builds the overlay/minigame host.
    ///   - onResolved: Called when the overlay finishes while still covering the world.
    ///     Prepare state, then call `returnToWorld.crossfadeToWorld` / `dismissWhileCovered`.
    ///     Invoke `done` inside that callback when all post-return work finishes so the presenter unlocks.
    func present(
        fadeWorldOut: Bool = true,
        makeViewController: @escaping () -> FullscreenOverlayHost,
        onResolved: @escaping (_ returnToWorld: OverlayReturn) -> Void
    ) {
        guard !isPresenting else { return }
        isPresenting = true

        let show = { [weak self] in
            guard let self else { return }
            let viewController = makeViewController()
            viewController.onFinished = { [weak self, weak viewController] in
                guard let self, let viewController else { return }
                viewController.onFinished = nil

                if fadeWorldOut {
                    let returnToWorld = OverlayReturn { [weak self] style, after in
                        guard let self else { return }
                        self.returnToWorld(
                            host: viewController,
                            style: style,
                            after: after
                        )
                    }
                    onResolved(returnToWorld)
                } else {
                    // No world fade on present (e.g. you-win): content fade, dismiss, then resolve.
                    viewController.fadeOutContent {
                        self.dependencies.dismiss(viewController) {
                            let returnToWorld = OverlayReturn { [weak self] _, after in
                                after {
                                    self?.isPresenting = false
                                }
                            }
                            onResolved(returnToWorld)
                        }
                    }
                }
            }
            self.dependencies.present(viewController)
        }

        if fadeWorldOut {
            dependencies.fadeWorldOut(Self.worldCrossfadeDuration, show)
        } else {
            show()
        }
    }

    private func returnToWorld(
        host: FullscreenOverlayHost,
        style: OverlayReturn.Style,
        after: @escaping (_ done: @escaping () -> Void) -> Void
    ) {
        let finishUnlock: () -> Void = { [weak self] in
            self?.isPresenting = false
        }

        switch style {
        case .crossfadeToWorld:
            crossfadeDismiss(host: host) {
                after(finishUnlock)
            }
        case .dismissWhileCovered:
            host.fadeOutContent { [weak self] in
                guard let self else { return }
                self.dependencies.dismiss(host) {
                    after(finishUnlock)
                }
            }
        }
    }

    /// Fades the entire overlay host out while fading the world in, then dismisses the host.
    private func crossfadeDismiss(
        host: FullscreenOverlayHost,
        completion: @escaping () -> Void
    ) {
        let duration = Self.worldCrossfadeDuration
        let latch = CompletionLatch(count: 2, completion: { [weak self] in
            self?.dependencies.dismiss(host, completion)
        })

        host.fadeOutHost(duration: duration) {
            latch.arrive()
        }

        dependencies.fadeWorldIn(duration) {
            latch.arrive()
        }
    }
}

/// Fires `completion` once after `count` arrivals (main-actor only).
@MainActor
private final class CompletionLatch {
    private var remaining: Int
    private let completion: () -> Void

    init(count: Int, completion: @escaping () -> Void) {
        remaining = count
        self.completion = completion
    }

    func arrive() {
        remaining -= 1
        guard remaining == 0 else { return }
        completion()
    }
}
