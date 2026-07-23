import CoreGraphics
import Foundation

/// Pure geometry for combat slash hit tests.
nonisolated enum CombatSlashGeometry {
    /// True when `points` fully cuts through the axis-aligned square centered at `center`
    /// with side length `side`. The path must enter across one edge and leave across a
    /// *different* edge (a poke that reverses out the same side does not count).
    static func slashBisectsSquare(
        points: [CGPoint],
        center: CGPoint,
        side: CGFloat
    ) -> Bool {
        guard points.count >= 2, side > 0 else { return false }
        let half = side * 0.5
        let rect = CGRect(
            x: center.x - half,
            y: center.y - half,
            width: side,
            height: side
        )

        var entryEdge: Int?
        var wasInside = rect.contains(points[0])

        for i in 1..<points.count {
            let a = points[i - 1]
            let b = points[i]
            let crossings = orderedBoundaryCrossings(a, b, rect: rect)

            if crossings.count >= 2 {
                // One segment spans the square — enter and exit on distinct edges.
                let first = crossings.first!.edge
                let last = crossings.last!.edge
                if first != last {
                    return true
                }
            }

            for crossing in crossings {
                let nowInside: Bool
                if wasInside {
                    // Leaving across this edge.
                    nowInside = false
                    if let entry = entryEdge, entry != crossing.edge {
                        return true
                    }
                    entryEdge = nil
                } else {
                    // Entering across this edge.
                    nowInside = true
                    entryEdge = crossing.edge
                }
                wasInside = nowInside
            }

            // Keep containment in sync when a segment ends inside without a clean
            // numeric crossing (e.g. endpoint lands exactly on the boundary).
            wasInside = rect.contains(b)
        }
        return false
    }

    struct BoundaryCrossing: Equatable {
        var t: CGFloat
        var edge: Int
    }

    /// Boundary crossings for segment a→b, sorted by parameter t along the segment.
    static func orderedBoundaryCrossings(
        _ a: CGPoint,
        _ b: CGPoint,
        rect: CGRect
    ) -> [BoundaryCrossing] {
        let edges: [(CGPoint, CGPoint)] = [
            (CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY)), // 0 bottom
            (CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY)), // 1 right
            (CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)), // 2 top
            (CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.minY)), // 3 left
        ]
        var hits: [BoundaryCrossing] = []
        for (index, edge) in edges.enumerated() {
            if let t = segmentIntersectionT(a, b, edge.0, edge.1) {
                hits.append(BoundaryCrossing(t: t, edge: index))
            }
        }
        hits.sort { $0.t < $1.t }

        // Deduplicate corner hits (same t on two edges) — keep the first.
        var unique: [BoundaryCrossing] = []
        for hit in hits {
            if unique.isEmpty || abs(unique.last!.t - hit.t) > 1e-4 {
                unique.append(hit)
            }
        }
        return unique
    }

    /// Parameter t on segment a→b where it intersects segment c→d, if any.
    static func segmentIntersectionT(
        _ a: CGPoint,
        _ b: CGPoint,
        _ c: CGPoint,
        _ d: CGPoint
    ) -> CGFloat? {
        let rbx = b.x - a.x
        let rby = b.y - a.y
        let sdx = d.x - c.x
        let sdy = d.y - c.y
        let den = rbx * sdy - rby * sdx
        guard abs(den) > 1e-8 else { return nil }

        let acx = c.x - a.x
        let acy = c.y - a.y
        let t = (acx * sdy - acy * sdx) / den
        let u = (acx * rby - acy * rbx) / den
        guard t >= -1e-6, t <= 1 + 1e-6, u >= -1e-6, u <= 1 + 1e-6 else {
            return nil
        }
        return min(1, max(0, t))
    }
}
