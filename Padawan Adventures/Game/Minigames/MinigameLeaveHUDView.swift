import SwiftUI
import UIKit

/// Full-bleed leave chrome matching `GameHUDView`'s flee button (bottom-trailing + `ScreenLayout`).
final class MinigameLeaveHUDView: UIView {
    var onLeave: (() -> Void)?

    private let leaveButton: UIButton
    private lazy var edgeInsets = ScreenEdgeInsetController(host: self)

    override init(frame: CGRect) {
        leaveButton = GameHUDView.makeFleeButton()
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if hit === leaveButton || hit?.isDescendant(of: leaveButton) == true {
            return hit
        }
        return nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        edgeInsets.update()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        edgeInsets.update()
    }

    private func setup() {
        backgroundColor = .clear
        isUserInteractionEnabled = true
        translatesAutoresizingMaskIntoConstraints = true

        leaveButton.accessibilityLabel = Strings.text("hud_leave")
        leaveButton.accessibilityIdentifier = "minigame.leave"
        leaveButton.addTarget(self, action: #selector(leaveTapped), for: .touchUpInside)
        addSubview(leaveButton)

        let leaveBottom = leaveButton.bottomAnchor.constraint(equalTo: bottomAnchor)
        let leaveTrailing = leaveButton.trailingAnchor.constraint(equalTo: trailingAnchor)
        edgeInsets.addBottom(leaveBottom)
        edgeInsets.addTrailing(leaveTrailing)
        NSLayoutConstraint.activate([leaveBottom, leaveTrailing])
        edgeInsets.update()
    }

    @objc private func leaveTapped() {
        playMenuSound("button_click")
        onLeave?()
    }
}

struct MinigameLeaveButtonHost: UIViewRepresentable {
    let onLeave: () -> Void

    func makeUIView(context: Context) -> MinigameLeaveHUDView {
        let view = MinigameLeaveHUDView()
        view.onLeave = onLeave
        return view
    }

    func updateUIView(_ uiView: MinigameLeaveHUDView, context: Context) {
        uiView.onLeave = onLeave
    }
}
