import SpriteKit
import SwiftUI

/// Hosts an SKScene in SwiftUI. Shared by every minigame variant.
struct SpriteKitSceneView<Scene: SKScene>: UIViewRepresentable {
    let scene: Scene

    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        view.allowsTransparency = false
        view.ignoresSiblingOrder = true
        view.presentScene(scene)
        return view
    }

    func updateUIView(_ uiView: SKView, context: Context) {
        if uiView.scene !== scene {
            uiView.presentScene(scene)
        }
    }
}
