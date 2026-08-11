import CoreGraphics
import Foundation

/// Layout math for the sound-out-word pit arena (pads, per-step candidate fan, prompt).
/// Pure and unit-testable.
nonisolated struct PitSoundOutWordGeometry: Equatable, Sendable {
    /// The prompt block hangs from the shared top chrome inset so the CRT plate grows downward.
    /// Expressed as a fraction because this geometry is pure; it matches `ScreenLayout` because
    /// landscape has no top safe-area inset to take the max against.
    static let promptTopFraction: CGFloat = 1 - ScreenLayout.edgeInsetFraction
    /// Vertical gap between tiles in a step, as a fraction of the tile side.
    static let candidateSpacingScale: CGFloat = 0.95
    /// Whole candidate fan sits this fraction below the pad mid-line.
    static let candidateFanDownShift: CGFloat = 0.30
    /// Horizontal per-tile jitter as a fraction of `tileSide`.
    static let candidateJitterXScale: CGFloat = 0.20
    /// Vertical per-tile jitter as a fraction of `tileSide`.
    static let candidateJitterYScale: CGFloat = 0.10

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

    /// Vertical centre of the candidate fan (pad mid-line shifted down).
    var candidateFanMidY: CGFloat {
        leftPadRect.midY * (1 - Self.candidateFanDownShift)
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

    /// Target max dimension for the word illustration.
    var promptMaxSide: CGFloat {
        min(sceneSize.width * 0.28, sceneSize.height * 0.16, tileSide * 1.8)
    }

    /// Height of the merged CRT prompt plate: illustration over the word band.
    /// Word line height is approximated at 1.3x the font size because `AppFont` is
    /// MainActor-isolated; word width is approximated with `promptMaxSide`.
    var promptBlockHeight: CGFloat {
        let fontSize = max(promptMaxSide * 0.28, 18)
        return MinigameCRTPromptPlate.plateSize(
            pictureSide: promptMaxSide,
            wordContent: CGSize(width: promptMaxSide, height: fontSize * 1.3)
        ).height
    }

    /// Centre of the top-anchored prompt block.
    var promptCenter: CGPoint {
        CGPoint(
            x: sceneSize.width * 0.5,
            y: sceneSize.height * Self.promptTopFraction - promptBlockHeight * 0.5
        )
    }

    /// Lowest point the prompt block reaches — the ceiling for the candidate fan.
    var promptBottomY: CGFloat { promptCenter.y - promptBlockHeight * 0.5 }

    var stepSpacing: CGFloat {
        (rightPadRect.minX - leftPadRect.maxX) / CGFloat(stepCount + 1)
    }

    func stepColumnX(_ step: Int) -> CGFloat {
        leftPadRect.maxX + stepSpacing * CGFloat(step + 1)
    }

    /// `count` tiles fanned vertically and centred on the (down-shifted) pad line.
    func candidateCenter(step: Int, candidate: Int, count: Int) -> CGPoint {
        let safeCount = max(count, 1)
        let x = stepColumnX(step)
        let spacing = candidateSpacing(for: safeCount)
        let midY = candidateFanMidY
        let offset = (CGFloat(safeCount - 1) / 2 - CGFloat(candidate)) * spacing
        return CGPoint(x: x, y: midY + offset)
    }

    /// Approximate on-screen footprint of a floor tile, used for overlap tests.
    var candidateFootprint: CGSize {
        CGSize(width: tileSide * 0.92, height: tileSide * 0.55)
    }

    /// One jittered offset per candidate. Rejection-sampled so the resulting tiles
    /// never overlap; falls back to smaller (then zero) jitter if needed.
    func candidateJitters(
        step: Int,
        count: Int,
        using rng: inout some RandomNumberGenerator
    ) -> [CGPoint] {
        let safeCount = max(count, 1)
        var jitters = Array(repeating: CGPoint.zero, count: safeCount)
        var positions: [CGPoint] = []
        positions.reserveCapacity(safeCount)

        for index in 0..<safeCount {
            let center = candidateCenter(step: step, candidate: index, count: safeCount)
            var placed = false
            for attempt in 0..<24 {
                let scale: CGFloat
                if attempt < 16 {
                    scale = 1
                } else if attempt < 20 {
                    scale = 0.5
                } else {
                    scale = 0
                }
                let jitter = randomCandidateJitter(scale: scale, using: &rng)
                let position = CGPoint(x: center.x + jitter.x, y: center.y + jitter.y)
                if positions.allSatisfy({ !candidatesOverlap($0, position) }) {
                    jitters[index] = jitter
                    positions.append(position)
                    placed = true
                    break
                }
            }
            if !placed {
                jitters[index] = .zero
                positions.append(center)
            }
        }
        return jitters
    }

    func randomCandidateJitter(
        scale: CGFloat = 1,
        using rng: inout some RandomNumberGenerator
    ) -> CGPoint {
        let clamped = max(0, min(scale, 1))
        let spanX = tileSide * Self.candidateJitterXScale * clamped
        let spanY = tileSide * Self.candidateJitterYScale * clamped
        return CGPoint(
            x: spanX == 0 ? 0 : CGFloat.random(in: -spanX...spanX, using: &rng),
            y: spanY == 0 ? 0 : CGFloat.random(in: -spanY...spanY, using: &rng)
        )
    }

    /// Axis-aligned footprint test — slightly conservative vs the isometric diamond.
    func candidatesOverlap(_ a: CGPoint, _ b: CGPoint) -> Bool {
        let size = candidateFootprint
        return abs(a.x - b.x) < size.width && abs(a.y - b.y) < size.height
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
        let topLimit = promptBottomY - tileSide * 0.15
        let bottomLimit = tileSide * 0.5
        let midY = candidateFanMidY

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
