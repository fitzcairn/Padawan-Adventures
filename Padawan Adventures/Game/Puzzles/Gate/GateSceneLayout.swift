import SpriteKit
import UIKit

extension GateScene {
    // MARK: - Layout

    var stagingRect: CGRect {
        // Aspect 3:1 landscape, ~40% of screen area, then shrunk 25%.
        let area = size.width * size.height * 0.40
        var width = sqrt(area * 3)
        var height = width / 3
        if width > size.width * 0.9 {
            width = size.width * 0.9
            height = width / 3
        }
        if height > size.height * 0.7 {
            height = size.height * 0.7
            width = height * 3
        }
        width *= 0.75
        height *= 0.75
        return CGRect(
            x: (size.width - width) * 0.5,
            y: (size.height - height) * 0.5,
            width: width,
            height: height
        )
    }

    /// Base token radius before letter/endpoint size adjustments.
    var letterRadius: CGFloat {
        min(size.width, size.height) * 0.07
    }

    /// Letter capacitors are 40% larger than the base radius.
    var letterCapacitorRadius: CGFloat {
        letterRadius * 1.4
    }

    /// Empty side capacitors are 40% smaller than the base radius.
    var endpointCapacitorRadius: CGFloat {
        letterRadius * 0.6
    }

    /// Top band reserved for the HUD word/timer (shared screen inset + label height).
    /// SpriteKit Y grows upward, so playable content must stay below `size.height - this`.
    var topHUDReservedHeight: CGFloat {
        let host = view
        let hostSize = host?.bounds.size ?? size
        let safeArea = host?.safeAreaInsets ?? .zero
        let topInset = ScreenLayout.uiInsets(size: hostSize, safeArea: safeArea).top
        // Matches SpellingProgressHUDView's 44pt bold word, plus a little breathing room under the label.
        let wordBand: CGFloat = 56
        return topInset + wordBand
    }

    /// Highest Y a letter/endpoint center may use without overlapping the HUD word band.
    func maxPlayableCenterY(for radius: CGFloat) -> CGFloat {
        size.height - topHUDReservedHeight - radius
    }

    /// Midpoint between the left screen edge and the left side of the staging box.
    var leftEndpointPosition: CGPoint {
        let rect = stagingRect
        let y = min(size.height * 0.5, maxPlayableCenterY(for: endpointCapacitorRadius))
        return CGPoint(x: rect.minX * 0.5, y: y)
    }

    /// Midpoint between the right side of the staging box and the right screen edge.
    var rightEndpointPosition: CGPoint {
        let rect = stagingRect
        let y = min(size.height * 0.5, maxPlayableCenterY(for: endpointCapacitorRadius))
        return CGPoint(x: (rect.maxX + size.width) * 0.5, y: y)
    }

    func buildPuzzle() {
        removeAllChildren()
        letterNodes = [:]
        connectorSegments = []
        electricityRefreshAccumulator = 0
        if let background = GateMinigameBackground.spelling(sceneSize: size) {
            addChild(background)
        }

        let rect = stagingRect
        let staging = SKShapeNode(rectOf: rect.size, cornerRadius: 10)
        staging.fillColor = .clear
        staging.strokeColor = .clear
        staging.lineWidth = 0
        staging.position = CGPoint(x: rect.midX, y: rect.midY)
        staging.zPosition = 1
        staging.name = "staging"
        addChild(staging)
        stagingNode = staging

        let left = makeEndpointNode(radius: endpointCapacitorRadius, name: "endpoint:left")
        left.position = leftEndpointPosition
        addChild(left)
        leftEndpointNode = left

        let right = makeEndpointNode(radius: endpointCapacitorRadius, name: "endpoint:right")
        right.position = rightEndpointPosition
        addChild(right)
        rightEndpointNode = right

        let radius = letterCapacitorRadius
        var placedCenters: [CGPoint] = [leftEndpointPosition, rightEndpointPosition]
        for token in engine.letters {
            let node = makeLetterNode(token: token, radius: radius)
            let position = placeLetter(radius: radius, avoiding: placedCenters)
            node.position = position
            placedCenters.append(position)
            addChild(node)
            letterNodes[token.id] = node
        }
    }

    func rebuildLayoutPreservingLetters() {
        let previousPositions = letterNodes.mapValues(\.position)
        buildPuzzle()
        let radius = letterCapacitorRadius
        var placedCenters: [CGPoint] = [leftEndpointPosition, rightEndpointPosition]
        // Restore prior positions when still valid and non-overlapping; otherwise re-place.
        for (id, node) in letterNodes {
            if let previous = previousPositions[id],
               isValidLetterPosition(previous, radius: radius, avoiding: placedCenters) {
                node.position = previous
                placedCenters.append(previous)
            } else {
                let position = placeLetter(radius: radius, avoiding: placedCenters)
                node.position = position
                placedCenters.append(position)
            }
        }
        updateCorrectOrderConnectors()
    }
    /// Minimum center-to-center distance so capacitors do not overlap (includes a small gap).
    func minCenterDistance(for radius: CGFloat) -> CGFloat {
        radius * 2 + 6
    }

    func placeLetter(radius: CGFloat, avoiding occupied: [CGPoint]) -> CGPoint {
        let inset = radius + 8
        let maxY = maxPlayableCenterY(for: radius)
        let minY = inset
        let bounds = CGRect(
            x: inset,
            y: minY,
            width: max(size.width - inset * 2, 1),
            height: max(maxY - minY, 1)
        )

        for _ in 0..<120 {
            let point = CGPoint(
                x: CGFloat.random(in: bounds.minX...bounds.maxX, using: &placementRNG),
                y: CGFloat.random(in: bounds.minY...bounds.maxY, using: &placementRNG)
            )
            if isValidLetterPosition(point, radius: radius, avoiding: occupied) {
                return point
            }
        }

        // Deterministic scan if random placement can't find a free slot.
        let step = minCenterDistance(for: radius)
        var y = bounds.maxY
        while y >= bounds.minY {
            var x = bounds.minX
            while x <= bounds.maxX {
                let point = CGPoint(x: x, y: y)
                if isValidLetterPosition(point, radius: radius, avoiding: occupied) {
                    return point
                }
                x += step
            }
            y -= step
        }

        // Last resort: keep searching with a tighter gap so letters still don't stack.
        return densestFallbackPosition(radius: radius, avoiding: occupied, bounds: bounds)
    }

    func densestFallbackPosition(
        radius: CGFloat,
        avoiding occupied: [CGPoint],
        bounds: CGRect
    ) -> CGPoint {
        let step = max(radius * 1.5, 8)
        var y = bounds.maxY
        while y >= bounds.minY {
            var x = bounds.minX
            while x <= bounds.maxX {
                let point = CGPoint(x: x, y: y)
                if isValidLetterPosition(point, radius: radius, avoiding: occupied, gap: 1) {
                    return point
                }
                x += step
            }
            y -= step
        }
        // Truly full screen: place at the first in-bounds point farthest from others.
        return farthestPoint(in: bounds, from: occupied) ?? CGPoint(x: bounds.midX, y: bounds.maxY)
    }

    func farthestPoint(in bounds: CGRect, from occupied: [CGPoint]) -> CGPoint? {
        guard !occupied.isEmpty else {
            return CGPoint(x: bounds.minX, y: bounds.maxY)
        }
        var best: CGPoint?
        var bestScore: CGFloat = -1
        let samples = 24
        for iy in 0...samples {
            for ix in 0...samples {
                let point = CGPoint(
                    x: bounds.minX + (bounds.width * CGFloat(ix) / CGFloat(samples)),
                    y: bounds.minY + (bounds.height * CGFloat(iy) / CGFloat(samples))
                )
                guard isOutsideStaging(point, radius: letterCapacitorRadius) else { continue }
                let score = occupied.map { hypot($0.x - point.x, $0.y - point.y) }.min() ?? 0
                if score > bestScore {
                    bestScore = score
                    best = point
                }
            }
        }
        return best
    }

    func isOutsideStaging(_ point: CGPoint, radius: CGFloat) -> Bool {
        let letterBounds = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        return !letterBounds.intersects(stagingRect.insetBy(dx: -4, dy: -4))
    }

    func isValidLetterPosition(
        _ point: CGPoint,
        radius: CGFloat,
        avoiding occupied: [CGPoint],
        gap: CGFloat? = nil
    ) -> Bool {
        let maxY = maxPlayableCenterY(for: radius)
        guard point.x >= radius,
              point.y >= radius,
              point.x <= size.width - radius,
              point.y <= maxY else {
            return false
        }
        guard isOutsideStaging(point, radius: radius) else { return false }

        let minDistance = gap.map { radius * 2 + $0 } ?? minCenterDistance(for: radius)
        for other in occupied {
            if hypot(other.x - point.x, other.y - point.y) < minDistance {
                return false
            }
        }
        return true
    }
}
