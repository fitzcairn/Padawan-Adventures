import Foundation
import CoreGraphics

/// Distinguishes tap-to-move from viewport drag.
struct ViewportGestureTracker: Sendable {
    static let panThreshold: CGFloat = 12

    private(set) var touchStart: CGPoint?
    private(set) var lastTouch: CGPoint?
    private(set) var isPanning: Bool = false
    private(set) var totalDragDistance: CGFloat = 0

    mutating func begin(at point: CGPoint) {
        touchStart = point
        lastTouch = point
        isPanning = false
        totalDragDistance = 0
    }

    /// Returns the scene-space drag delta since the last move, if any.
    mutating func move(to point: CGPoint) -> CGPoint? {
        guard let last = lastTouch, let start = touchStart else { return nil }

        let step = CGPoint(x: point.x - last.x, y: point.y - last.y)
        lastTouch = point

        let dx = point.x - start.x
        let dy = point.y - start.y
        totalDragDistance = hypot(dx, dy)

        if totalDragDistance >= Self.panThreshold {
            isPanning = true
        }

        guard isPanning else { return nil }
        return step
    }

    /// Ends the gesture. Returns `true` if it should be treated as a tap (not a pan).
    mutating func end() -> Bool {
        let wasTap = !isPanning
        touchStart = nil
        lastTouch = nil
        isPanning = false
        totalDragDistance = 0
        return wasTap
    }

    mutating func cancel() {
        _ = end()
    }
}
