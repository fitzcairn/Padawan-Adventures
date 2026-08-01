import SwiftUI
import UIKit

/// Pins a UIKit HUD view inside a clear container for SwiftUI layout.
struct HUDHostRepresentable<HUD: UIView>: UIViewRepresentable {
    let makeHUD: () -> HUD
    let update: (HUD) -> Void

    final class Coordinator {
        var hud: HUD?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        container.isUserInteractionEnabled = false

        let hud = makeHUD()
        hud.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hud)
        NSLayoutConstraint.activate([
            hud.topAnchor.constraint(equalTo: container.topAnchor),
            hud.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hud.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hud.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        context.coordinator.hud = hud
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let hud = context.coordinator.hud {
            update(hud)
        }
    }
}
