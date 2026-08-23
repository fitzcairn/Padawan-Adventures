import CoreGraphics
import Foundation

/// Trailing inventory column: 3 CRT plates with a gap of `0.10 ×` plate height.
nonisolated struct InventorySlotLayout: Equatable, Sendable {
    static let sideFractionOfHUD: CGFloat = 0.14
    static let gapFractionOfSide: CGFloat = 0.10
    /// Trailing column width as a fraction of HUD height (matches `GameHUDView`).
    static let columnWidthFraction: CGFloat = 0.16

    var side: CGFloat

    var gap: CGFloat { side * Self.gapFractionOfSide }
    var pitch: CGFloat { side + gap }
    var clusterHeight: CGFloat { 3 * side + 2 * gap }

    static func compute(hudHeight: CGFloat, availableHeight: CGFloat) -> InventorySlotLayout {
        let height = max(hudHeight, 1)
        var side = height * sideFractionOfHUD
        let available = max(availableHeight, 0)
        if available > 0 {
            let maxSide = available / (3 + 2 * gapFractionOfSide)
            if maxSide > 0 {
                side = min(side, maxSide)
            }
        }
        side = max(side, 1)
        return InventorySlotLayout(side: side)
    }
}

enum InventorySlotInteraction: Equatable {
    case world
    case shop
}
