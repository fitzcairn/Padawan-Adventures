import SwiftUI
import UIKit

/// Thin UIKit host for SwiftUI overlay/minigame content presented over the game.
/// Provides dark chrome, content fade in/out, and the shared finish callback.
final class FullscreenOverlayHost: LandscapeHostingController {
    /// Invoked when the overlay/minigame is ready to dismiss.
    var onFinished: (() -> Void)?

    static let overlayBackgroundColor = UIColor(white: 0.08, alpha: 1)
    static let contentFadeDuration: TimeInterval = 0.2

    private let contentContainer = UIView()
    private let hostingController: UIHostingController<AnyView>

    init<Content: View>(@ViewBuilder content: @escaping (_ finish: @escaping () -> Void) -> Content) {
        let finishBox = FinishBox()
        let root = AnyView(
            content { finishBox.finish() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
        hostingController = UIHostingController(rootView: root)
        super.init(nibName: nil, bundle: nil)
        finishBox.handler = { [weak self] in
            self?.finish()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Self.overlayBackgroundColor

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.alpha = 0
        view.addSubview(contentContainer)
        NSLayoutConstraint.activate([
            contentContainer.topAnchor.constraint(equalTo: view.topAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        hostingController.view.backgroundColor = .clear
        addChild(hostingController)
        contentContainer.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
        hostingController.didMove(toParent: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIView.animate(withDuration: Self.contentFadeDuration) {
            self.contentContainer.alpha = 1
        }
    }

    /// Fades content out, then calls `completion` (used by the shared presenter before dismiss).
    func fadeOutContent(
        duration: TimeInterval = contentFadeDuration,
        completion: @escaping () -> Void
    ) {
        UIView.animate(withDuration: duration, animations: {
            self.contentContainer.alpha = 0
        }, completion: { _ in
            completion()
        })
    }

    func finish() {
        onFinished?()
    }
}

/// Avoids capturing `self` before `super.init` when building the SwiftUI root.
private final class FinishBox {
    var handler: (() -> Void)?

    func finish() {
        handler?()
    }
}
