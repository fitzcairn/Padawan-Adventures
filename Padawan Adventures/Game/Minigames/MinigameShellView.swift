import SpriteKit
import SwiftUI

/// Shared GeometryReader/ZStack shell for every minigame variant.
struct MinigameShellView<Scene: SKScene, HUD: View, Overlay: View>: View {
    let scene: Scene?
    let accessibilityRootID: String
    let ensureScene: (CGSize) -> Void
    let updateSceneSize: (CGSize) -> Void
    var onAppear: (() -> Void)?
    var includesHUDLayer: Bool = true
    /// When set, shows the level-HUD flee control (bottom-trailing) to leave without completing.
    var onLeave: (() -> Void)? = nil
    @ViewBuilder var hud: HUD
    @ViewBuilder var overlay: Overlay

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                OverlayChrome.backgroundColor.ignoresSafeArea()

                if let scene {
                    SpriteKitSceneView(scene: scene)
                        .ignoresSafeArea()
                }

                if includesHUDLayer {
                    hud
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }

                if let onLeave {
                    MinigameLeaveButtonHost(onLeave: onLeave)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea()
                }

                overlay
            }
            .onAppear {
                onAppear?()
                ensureScene(proxy.size)
            }
            .onChange(of: proxy.size) { _, newSize in
                updateSceneSize(newSize)
            }
        }
        .accessibilityIdentifier(accessibilityRootID)
    }
}
