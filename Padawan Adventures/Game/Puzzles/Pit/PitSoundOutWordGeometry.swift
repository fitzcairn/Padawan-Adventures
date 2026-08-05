import CoreGraphics
import Foundation

/// Layout math for the sound-out-word pit arena (pads, per-step candidate fan, prompt).
/// Pure and unit-testable.
nonisolated struct PitSoundOutWordGeometry: Equatable, Sendable {
    static let promptYFraction: CGFloat = 0.88
    /// Vertical gap between tiles in a step, as a fraction of the tile side.
    static let candidateSpacingScale: CGFloat = 0.95

    var sceneSize: CGSize
    /// From `PitArenaLayout.floorPadBounds(config:).size`.
    var padSize: CGSize
    /// Number of steps == graphemes in the word.
    var stepCount: Int

    init(sceneSize: CGSize, padSize: CGSize, stepCount: Int) {
        self.sceneSize = sceneSize
        self.padSize = padSize
        self.stepCount = max(stepCount, 1)
    }

    var leftPadRect: CGRect {
        let padY = (sceneSize.height - padSize.height) * 0.5
        return CGRect(x: 0, y: padY, width: padSize.width, height: padSize.height)
    }

    var rightPadRect: CGRect {
        let padY = (sceneSize.height - padSize.height) * 0.5
        return CGRect(
            x: sceneSize.width - padSize.width,
            y: padY,
            width: padSize.width,
            height: padSize.height
        )
    }

    /// One isometric tile wide — half the 2x2 pad footprint.
    var tileSide: CGFloat {
        padSize.width * 0.5
    }

    /// Top-middle anchor for the word illustration + text row.
    var promptCenter: CGPoint {
        CGPoint(
            x: sceneSize.width * 0.5,
            y: sceneSize.height * Self.promptYFraction
        )
    }

    /// Target max dimension for the word illustration.
    var promptMaxSide: CGFloat {
        min(sceneSize.width * 0.28, sceneSize.height * 0.16, tileSide * 1.8)
    }

    var stepSpacing: CGFloat {
        (rightPadRect.minX - leftPadRect.maxX) / CGFloat(stepCount + 1)
    }

    func stepColumnX(_ step: Int) -> CGFloat {
        leftPadRect.maxX + stepSpacing * CGFloat(step + 1)
    }

    /// `count` tiles fanned vertically and centred on the pad line.
    func candidateCenter(step: Int, candidate: Int, count: Int) -> CGPoint {
        let safeCount = max(count, 1)
        let x = stepColumnX(step)
        let spacing = candidateSpacing(for: safeCount)
        let midY = leftPadRect.midY
        let offset = (CGFloat(safeCount - 1) / 2 - CGFloat(candidate)) * spacing
        return CGPoint(x: x, y: midY + offset)
    }

    /// Index of the candidate whose centre is closest to `point`.
    func nearestCandidate(to point: CGPoint, step: Int, count: Int) -> Int {
        let safeCount = max(count, 1)
        var bestIndex = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for index in 0..<safeCount {
            let center = candidateCenter(step: step, candidate: index, count: safeCount)
            let distance = hypot(point.x - center.x, point.y - center.y)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    /// Vertical spacing shrunk when needed so the fan stays between the prompt and the floor.
    private func candidateSpacing(for count: Int) -> CGFloat {
        var spacing = tileSide * Self.candidateSpacingScale
        guard count > 1 else { return spacing }

        let halfSpan = CGFloat(count - 1) / 2
        let topLimit = promptCenter.y - promptMaxSide * 0.75
        let bottomLimit = tileSide * 0.5
        let midY = leftPadRect.midY

        let topY = midY + halfSpan * spacing
        if topY > topLimit, halfSpan > 0 {
            spacing = min(spacing, (topLimit - midY) / halfSpan)
        }
        let bottomY = midY - halfSpan * spacing
        if bottomY < bottomLimit, halfSpan > 0 {
            spacing = min(spacing, (midY - bottomLimit) / halfSpan)
        }
        return max(spacing, 0)
    }
}
