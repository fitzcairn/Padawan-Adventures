import CoreGraphics
import Testing
@testable import Padawan_Adventures

struct ViewportGestureTrackerTests {
    @Test func shortTouchIsTap() {
        var tracker = ViewportGestureTracker()
        tracker.begin(at: .zero)
        _ = tracker.move(to: CGPoint(x: 5, y: 0))
        let wasTap = tracker.end()
        #expect(wasTap)
    }

    @Test func longDragIsPan() {
        var tracker = ViewportGestureTracker()
        tracker.begin(at: .zero)
        let delta = tracker.move(to: CGPoint(x: ViewportGestureTracker.panThreshold + 1, y: 0))
        #expect(delta != nil)
        #expect(tracker.isPanning)
        let wasTap = tracker.end()
        #expect(!wasTap)
    }

    @Test func panReportsIncrementalDeltas() {
        var tracker = ViewportGestureTracker()
        tracker.begin(at: .zero)
        _ = tracker.move(to: CGPoint(x: 20, y: 0))
        let second = tracker.move(to: CGPoint(x: 30, y: 5))
        #expect(second?.x == 10)
        #expect(second?.y == 5)
    }
}
