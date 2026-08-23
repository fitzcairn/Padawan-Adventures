import CoreGraphics
import Foundation

/// Fires once per merchant the first time their standing point is in the camera.
struct MerchantVisibilityTracker {
    struct Candidate: Equatable, Sendable {
        var id: UUID
        var worldPoint: CGPoint
        var isShown: Bool
    }

    private var announcedIDs: Set<UUID> = []

    mutating func consumeNewlyVisible(
        merchants: [Candidate],
        focus: CGPoint,
        viewCenter: CGPoint,
        viewSize: CGSize,
        scale: CGFloat = 1
    ) -> [UUID] {
        let liveIDs = Set(merchants.map(\.id))
        announcedIDs = announcedIDs.intersection(liveIDs)

        var newlyVisible: [UUID] = []
        for merchant in merchants {
            guard merchant.isShown, !announcedIDs.contains(merchant.id) else { continue }
            guard IsometricMath.isOnScreen(
                worldPoint: merchant.worldPoint,
                focus: focus,
                viewCenter: viewCenter,
                viewSize: viewSize,
                scale: scale
            ) else { continue }
            announcedIDs.insert(merchant.id)
            newlyVisible.append(merchant.id)
        }
        return newlyVisible
    }
}
