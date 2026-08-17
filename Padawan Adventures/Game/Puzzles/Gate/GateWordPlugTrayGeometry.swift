import CoreGraphics
import Foundation

/// Layout math for the word-plug letter tray. Pure and unit-testable.
nonisolated struct GateWordPlugTrayGeometry: Equatable, Sendable {
    static let spacingScale: CGFloat = 1.2
    static let maxRows = 2
    static let minimumDiameter: CGFloat = 36
    /// Gap between the top of the tray stack and the plate grid.
    static let boardGap: CGFloat = 8

    var count: Int
    var diameter: CGFloat
    var sceneSize: CGSize
    var leftInset: CGFloat
    var rightInset: CGFloat

    var spacing: CGFloat { max(diameter * Self.spacingScale, diameter) }
    var radius: CGFloat { diameter * 0.5 }
    var rowGap: CGFloat { max(diameter * (Self.spacingScale - 1), 0) }

    var usableWidth: CGFloat {
        max(sceneSize.width - leftInset - rightInset, 0)
    }

    /// How many plug circles fit in one centered row.
    var maxPerRow: Int {
        guard count > 0, diameter > 0 else { return 1 }
        let budget = usableWidth - diameter
        if budget < -0.5 { return 1 }
        return max(1, 1 + Int(floor((budget + 0.0001) / spacing)))
    }

    var rowCount: Int {
        guard count > 0 else { return 0 }
        if count <= maxPerRow { return 1 }
        return Self.maxRows
    }

    /// Extra plug goes on the bottom row when wrapping (5 → 2 + 3).
    var topRowCount: Int {
        guard rowCount == 2 else { return max(count, 0) }
        return count / 2
    }

    var bottomRowCount: Int { max(count - topRowCount, 0) }

    var stackHeight: CGFloat {
        let rows = max(rowCount, 1)
        return CGFloat(rows) * diameter + CGFloat(max(rows - 1, 0)) * rowGap
    }

    func fitsHorizontally() -> Bool {
        guard count > 0 else { return true }
        return maxPerRow >= max(topRowCount, bottomRowCount)
    }

    func fitsVertically(boardBottomY: CGFloat, bottomInset: CGFloat = 0) -> Bool {
        stackHeight + Self.boardGap + max(bottomInset, 0) <= max(boardBottomY, 0) + 0.5
    }

    /// Homes in fill order: top row left-to-right, then bottom row.
    func homes(bottomInset: CGFloat, boardBottomY: CGFloat) -> [CGPoint] {
        guard count > 0 else { return [] }
        let height = stackHeight
        let ceiling = boardBottomY - Self.boardGap - height * 0.5
        let stackCenterY = ScreenLayout.bottomRowCenterY(
            rowHeight: height,
            bottomInset: bottomInset,
            ceiling: ceiling
        )
        let bottomY = stackCenterY - height * 0.5 + diameter * 0.5
        let topY = stackCenterY + height * 0.5 - diameter * 0.5
        if rowCount <= 1 {
            return rowHomes(count: count, y: bottomY)
        }
        return rowHomes(count: topRowCount, y: topY)
            + rowHomes(count: bottomRowCount, y: bottomY)
    }

    static func fittedDiameter(
        count: Int,
        boardDiameter: CGFloat,
        sceneSize: CGSize,
        leftInset: CGFloat,
        rightInset: CGFloat,
        bottomInset: CGFloat,
        boardBottomY: CGFloat
    ) -> CGFloat {
        let floor = max(minimumDiameter, boardDiameter * 0.5)
        var diameter = max(boardDiameter, floor)
        for _ in 0..<24 {
            let geo = Self(
                count: count,
                diameter: diameter,
                sceneSize: sceneSize,
                leftInset: leftInset,
                rightInset: rightInset
            )
            if geo.fitsHorizontally(),
               geo.fitsVertically(boardBottomY: boardBottomY, bottomInset: bottomInset) {
                return diameter
            }
            if diameter <= floor + 0.5 { return floor }
            diameter = max(floor, diameter * 0.9)
        }
        return floor
    }

    static func layout(
        count: Int,
        boardDiameter: CGFloat,
        sceneSize: CGSize,
        leftInset: CGFloat,
        rightInset: CGFloat,
        bottomInset: CGFloat,
        boardBottomY: CGFloat
    ) -> (diameter: CGFloat, homes: [CGPoint]) {
        let diameter = fittedDiameter(
            count: count,
            boardDiameter: boardDiameter,
            sceneSize: sceneSize,
            leftInset: leftInset,
            rightInset: rightInset,
            bottomInset: bottomInset,
            boardBottomY: boardBottomY
        )
        let geo = Self(
            count: count,
            diameter: diameter,
            sceneSize: sceneSize,
            leftInset: leftInset,
            rightInset: rightInset
        )
        return (diameter, geo.homes(bottomInset: bottomInset, boardBottomY: boardBottomY))
    }

    private func rowHomes(count: Int, y: CGFloat) -> [CGPoint] {
        guard count > 0 else { return [] }
        let span = CGFloat(count - 1) * spacing
        let minX = leftInset + radius
        let maxX = sceneSize.width - rightInset - radius
        let centerX = sceneSize.width * 0.5
        var startX = centerX - span * 0.5
        if startX < minX { startX = minX }
        if startX + span > maxX { startX = maxX - span }
        return (0..<count).map { index in
            let x = min(max(startX + CGFloat(index) * spacing, minX), maxX)
            return CGPoint(x: x, y: y)
        }
    }
}
