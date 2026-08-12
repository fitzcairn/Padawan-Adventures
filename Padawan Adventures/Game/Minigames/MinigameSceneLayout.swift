import SpriteKit
import UIKit

/// Screen-edge layout for in-scene chrome, shared by every minigame arena.
///
/// Background art is width-fit, so on a screen taller than the art it falls short of the
/// top and bottom edges. Rows of interactive sprites anchor to these insets instead, which
/// keeps them the same distance from the screen edge on every device.
extension SKScene {
    var chromeInsets: UIEdgeInsets {
        ScreenLayout.chromeInsets(sceneSize: size, viewSafeArea: view?.safeAreaInsets ?? .zero)
    }

    /// Center Y for a bottom row of `rowHeight`-tall sprites, kept at or below `ceiling`.
    ///
    /// Uses the swipe-row inset so the bar sits above the home-indicator gesture zone.
    func bottomRowCenterY(rowHeight: CGFloat, ceiling: CGFloat) -> CGFloat {
        ScreenLayout.bottomRowCenterY(
            rowHeight: rowHeight,
            bottomInset: ScreenLayout.swipeRowBottomInset(
                sceneHeight: size.height,
                chromeBottom: chromeInsets.bottom
            ),
            ceiling: ceiling
        )
    }
}
