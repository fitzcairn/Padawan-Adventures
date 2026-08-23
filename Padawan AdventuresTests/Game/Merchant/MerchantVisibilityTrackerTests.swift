import CoreGraphics
import Foundation
import Testing
@testable import Padawan_Adventures

struct MerchantVisibilityTrackerTests {
    private let viewCenter = CGPoint(x: 400, y: 300)
    private let viewSize = CGSize(width: 800, height: 600)
    private let focus = CGPoint(x: 10, y: 20)

    @Test func announcesOnceWhenMerchantEntersCamera() {
        var tracker = MerchantVisibilityTracker()
        let id = UUID()
        let offscreen = MerchantVisibilityTracker.Candidate(
            id: id,
            worldPoint: CGPoint(x: focus.x + 900, y: focus.y),
            isShown: true
        )
        #expect(
            tracker.consumeNewlyVisible(
                merchants: [offscreen],
                focus: focus,
                viewCenter: viewCenter,
                viewSize: viewSize
            ).isEmpty
        )

        let onscreen = MerchantVisibilityTracker.Candidate(
            id: id,
            worldPoint: focus,
            isShown: true
        )
        #expect(
            tracker.consumeNewlyVisible(
                merchants: [onscreen],
                focus: focus,
                viewCenter: viewCenter,
                viewSize: viewSize
            ) == [id]
        )
        #expect(
            tracker.consumeNewlyVisible(
                merchants: [onscreen],
                focus: focus,
                viewCenter: viewCenter,
                viewSize: viewSize
            ).isEmpty
        )
    }

    @Test func ignoresHiddenMerchantsEvenWhenInCamera() {
        var tracker = MerchantVisibilityTracker()
        let id = UUID()
        let hidden = MerchantVisibilityTracker.Candidate(
            id: id,
            worldPoint: focus,
            isShown: false
        )
        #expect(
            tracker.consumeNewlyVisible(
                merchants: [hidden],
                focus: focus,
                viewCenter: viewCenter,
                viewSize: viewSize
            ).isEmpty
        )
    }

    @Test func canAnnounceAgainAfterMerchantDespawns() {
        var tracker = MerchantVisibilityTracker()
        let first = UUID()
        let onscreen = MerchantVisibilityTracker.Candidate(
            id: first,
            worldPoint: focus,
            isShown: true
        )
        #expect(
            tracker.consumeNewlyVisible(
                merchants: [onscreen],
                focus: focus,
                viewCenter: viewCenter,
                viewSize: viewSize
            ) == [first]
        )
        _ = tracker.consumeNewlyVisible(
            merchants: [],
            focus: focus,
            viewCenter: viewCenter,
            viewSize: viewSize
        )
        let second = UUID()
        let next = MerchantVisibilityTracker.Candidate(
            id: second,
            worldPoint: focus,
            isShown: true
        )
        #expect(
            tracker.consumeNewlyVisible(
                merchants: [next],
                focus: focus,
                viewCenter: viewCenter,
                viewSize: viewSize
            ) == [second]
        )
    }
}

struct MerchantOnScreenTests {
    @Test func worldPointAtFocusIsOnScreen() {
        let focus = CGPoint(x: 12, y: -8)
        let viewCenter = CGPoint(x: 400, y: 300)
        #expect(
            IsometricMath.isOnScreen(
                worldPoint: focus,
                focus: focus,
                viewCenter: viewCenter,
                viewSize: CGSize(width: 800, height: 600)
            )
        )
    }

    @Test func worldPointFarFromFocusIsOffScreen() {
        let focus = CGPoint.zero
        #expect(
            !IsometricMath.isOnScreen(
                worldPoint: CGPoint(x: 2000, y: 0),
                focus: focus,
                viewCenter: CGPoint(x: 400, y: 300),
                viewSize: CGSize(width: 800, height: 600)
            )
        )
    }

    @Test func emptyViewIsNeverOnScreen() {
        #expect(
            !IsometricMath.isOnScreen(
                worldPoint: .zero,
                focus: .zero,
                viewCenter: .zero,
                viewSize: .zero
            )
        )
    }
}
