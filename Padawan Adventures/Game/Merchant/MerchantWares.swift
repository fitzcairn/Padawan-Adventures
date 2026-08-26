import CoreGraphics
import Foundation

/// Selects and lays out merchant wares on the shop mat.
nonisolated enum MerchantWares {
    static let maxCount = 4
    /// Empty center of `merchant-bg` (fractions of the aspect-fitted image).
    static let playWidthFraction: CGFloat = 0.60
    static let playHeightFraction: CGFloat = 0.56
    static let minGapPoints: CGFloat = 12
    static let minGapSpriteFraction: CGFloat = 0.25
    static let gridColumns = 2
    static let gridRows = 2
    /// Shrinks the centered 2×2 footprint relative to raw cell size + gap.
    static let gridScale: CGFloat = 0.90
    /// ± fraction of each stack's width / height after the 2×2 slot is chosen.
    static let positionJitterFraction: CGFloat = 0.05

    /// Unique ware ids for this level. Guaranteed `min_level == order` first (sorted, cap 4),
    /// then fill from `min_level <= order` using `seed`.
    static func selectIDs(
        catalog: [String: MerchantItemDefinition],
        levelOrder: Int,
        seed: UInt64
    ) -> [String] {
        let order = max(levelOrder, 1)
        let guaranteed = catalog
            .filter { $0.value.minLevel == order }
            .map(\.key)
            .sorted()
        if guaranteed.count >= maxCount {
            return Array(guaranteed.prefix(maxCount))
        }

        var selected = guaranteed
        let fillers = catalog
            .filter { $0.value.minLevel < order && $0.value.minLevel >= 1 }
            .map(\.key)
            .sorted()
        var rng = SeededGenerator(seed: seed)
        var pool = fillers
        pool.shuffle(using: &rng)
        for id in pool {
            if selected.count >= maxCount { break }
            if !selected.contains(id) {
                selected.append(id)
            }
        }
        return selected
    }

    static func aspectFit(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    static func playArea(in displayedBackground: CGRect) -> CGRect {
        let width = displayedBackground.width * playWidthFraction
        let height = displayedBackground.height * playHeightFraction
        return CGRect(
            x: displayedBackground.midX - width / 2,
            y: displayedBackground.midY - height / 2,
            width: width,
            height: height
        )
    }

    /// Scale so the shorter axis equals `slotSide` (inventory square height).
    static func fittedSize(pixelSize: CGSize, slotSide: CGFloat) -> CGSize {
        let width = max(pixelSize.width, 0.001)
        let height = max(pixelSize.height, 0.001)
        let scale = slotSide / min(width, height)
        return CGSize(width: width * scale, height: height * scale)
    }

    /// Places `itemIDs` on a center-aligned 2×2 grid in `playArea`, then nudges
    /// each stack by ±`positionJitterFraction` of its size. Scale and slots come
    /// from `fitItemIDs` so remaining wares stay put after a purchase.
    static func layout(
        itemIDs: [String],
        playArea: CGRect,
        slotSide: CGFloat,
        pixelSizes: [String: CGSize] = [:],
        fitItemIDs: [String]? = nil,
        seed: UInt64
    ) -> MerchantWaresLayout {
        let visible = Set(itemIDs)
        guard !itemIDs.isEmpty, playArea.width > 1, playArea.height > 1 else {
            return MerchantWaresLayout(spriteSide: 0, gap: 0, stacks: [])
        }

        let scaleIDs = fitItemIDs ?? itemIDs
        var side = max(slotSide, 1)
        let minSide: CGFloat = 8
        func displaySize(for id: String, side: CGFloat) -> CGSize {
            fittedSize(pixelSize: pixelSizes[id] ?? CGSize(width: 1, height: 1), slotSide: side)
        }
        func stackSize(for id: String, side: CGFloat) -> CGSize {
            let display = displaySize(for: id, side: side)
            return CGSize(
                width: display.width,
                height: display.height + 4 + coinSide(spriteSide: side) + 4 + priceHeight(spriteSide: side)
            )
        }
        while side > minSide {
            let sizes = scaleIDs.map { stackSize(for: $0, side: side) }
            let gap = gapWidth(spriteSide: side)
            let maxWidth = sizes.map(\.width).max() ?? 0
            let maxHeight = sizes.map(\.height).max() ?? 0
            if maxWidth <= playArea.width,
               maxHeight <= playArea.height,
               CGFloat(gridColumns) * maxWidth + gap <= playArea.width,
               CGFloat(gridRows) * maxHeight + gap <= playArea.height
            {
                break
            }
            side *= 0.92
        }

        let gap = gapWidth(spriteSide: side)
        let sizes = scaleIDs.map { stackSize(for: $0, side: side) }
        let cellSize = CGSize(
            width: sizes.map(\.width).max() ?? side,
            height: sizes.map(\.height).max() ?? side
        )
        let grid = gridRect(cellSize: cellSize, in: playArea, gap: gap)
        let cellGap = gap * gridScale
        var rng = SeededGenerator(seed: seed)

        var stacks: [MerchantWareStackFrame] = []
        stacks.reserveCapacity(scaleIDs.count)
        for (index, id) in scaleIDs.enumerated() {
            let display = displaySize(for: id, side: side)
            let stack = stackSize(for: id, side: side)
            let cell = gridCell(index: index, in: grid, gap: cellGap)
            let base = centeredOrigin(stack: stack, in: cell)
            let origin = jitteredOrigin(base: base, stack: stack, in: playArea, rng: &rng)
            let frame = stackFrame(itemID: id, origin: origin, display: display, spriteSide: side)
            if visible.contains(id) {
                stacks.append(frame)
            }
        }
        return MerchantWaresLayout(spriteSide: side, gap: gap, stacks: stacks)
    }

    static func stackFrame(
        itemID: String,
        origin: CGPoint,
        display: CGSize,
        spriteSide: CGFloat
    ) -> MerchantWareStackFrame {
        let coin = coinSide(spriteSide: spriteSide)
        let price = priceHeight(spriteSide: spriteSide)
        return MerchantWareStackFrame(
            itemID: itemID,
            spriteFrame: CGRect(x: origin.x, y: origin.y, width: display.width, height: display.height),
            coinFrame: CGRect(
                x: origin.x + (display.width - coin) / 2,
                y: origin.y + display.height + 4,
                width: coin,
                height: coin
            ),
            priceFrame: CGRect(
                x: origin.x,
                y: origin.y + display.height + 4 + coin + 4,
                width: display.width,
                height: price
            )
        )
    }

    static func gapWidth(spriteSide: CGFloat) -> CGFloat {
        max(minGapPoints, spriteSide * minGapSpriteFraction)
    }

    static func coinSide(spriteSide: CGFloat) -> CGFloat {
        spriteSide * 0.36
    }

    static func priceHeight(spriteSide: CGFloat) -> CGFloat {
        max(14, spriteSide * 0.28)
    }

    static func stackSize(spriteSide: CGFloat) -> CGSize {
        let height = spriteSide + 4 + coinSide(spriteSide: spriteSide) + 4 + priceHeight(spriteSide: spriteSide)
        return CGSize(width: spriteSide, height: height)
    }

    /// Centered 2×2 box that holds `cellSize` slots plus one gap between them.
    static func gridRect(cellSize: CGSize, in playArea: CGRect, gap: CGFloat) -> CGRect {
        guard playArea.width > 1, playArea.height > 1 else { return playArea }
        let width = min(
            playArea.width,
            (CGFloat(gridColumns) * cellSize.width + CGFloat(gridColumns - 1) * gap) * gridScale
        )
        let height = min(
            playArea.height,
            (CGFloat(gridRows) * cellSize.height + CGFloat(gridRows - 1) * gap) * gridScale
        )
        return CGRect(
            x: playArea.midX - width / 2,
            y: playArea.midY - height / 2,
            width: max(width, 1),
            height: max(height, 1)
        )
    }

    static func gridCell(index: Int, in grid: CGRect, gap: CGFloat) -> CGRect {
        let column = index % gridColumns
        let row = index / gridColumns
        let cellWidth = max((grid.width - CGFloat(gridColumns - 1) * gap) / CGFloat(gridColumns), 1)
        let cellHeight = max((grid.height - CGFloat(gridRows - 1) * gap) / CGFloat(gridRows), 1)
        return CGRect(
            x: grid.minX + CGFloat(column) * (cellWidth + gap),
            y: grid.minY + CGFloat(row) * (cellHeight + gap),
            width: cellWidth,
            height: cellHeight
        )
    }

    static func centeredOrigin(stack: CGSize, in cell: CGRect) -> CGPoint {
        CGPoint(x: cell.midX - stack.width / 2, y: cell.midY - stack.height / 2)
    }

    static func jitteredOrigin(
        base: CGPoint,
        stack: CGSize,
        in playArea: CGRect,
        rng: inout SeededGenerator
    ) -> CGPoint {
        let dx = CGFloat.random(
            in: -positionJitterFraction...positionJitterFraction,
            using: &rng
        ) * stack.width
        let dy = CGFloat.random(
            in: -positionJitterFraction...positionJitterFraction,
            using: &rng
        ) * stack.height
        return CGPoint(
            x: clamp(base.x + dx, min: playArea.minX, max: playArea.maxX - stack.width),
            y: clamp(base.y + dy, min: playArea.minY, max: playArea.maxY - stack.height)
        )
    }

    private static func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        if max < min { return min }
        return Swift.min(Swift.max(value, min), max)
    }
}

nonisolated struct MerchantWareStackFrame: Equatable, Sendable {
    var itemID: String
    var spriteFrame: CGRect
    var coinFrame: CGRect
    var priceFrame: CGRect

    var bounds: CGRect {
        spriteFrame.union(coinFrame).union(priceFrame)
    }
}

nonisolated struct MerchantWaresLayout: Equatable, Sendable {
    var spriteSide: CGFloat
    var gap: CGFloat
    var stacks: [MerchantWareStackFrame]
}

/// Drop evaluation for a ware dragged onto (or off) an inventory slot.
nonisolated enum MerchantDropOutcome: Equatable, Sendable {
    case ignoredOutside
    case sameItemInSlot
    case soldOut
    case cannotAfford
    case purchaseEmptySlot
    case confirmReplace
}

nonisolated enum MerchantPurchase {
    static func outcome(
        itemID: String,
        slotIndex: Int?,
        slots: [String],
        price: Int,
        coins: Int,
        limit: Int = 0
    ) -> MerchantDropOutcome {
        guard let slotIndex, slots.indices.contains(slotIndex) else {
            return .ignoredOutside
        }
        let occupant = slots[slotIndex]
        if occupant == itemID {
            return .sameItemInSlot
        }
        let held = MerchantItemDefinition.heldCount(itemID: itemID, in: slots)
        if !MerchantItemDefinition.canHoldAnother(limit: limit, held: held) {
            return .soldOut
        }
        if coins < price {
            return .cannotAfford
        }
        if occupant.isEmpty {
            return .purchaseEmptySlot
        }
        return .confirmReplace
    }

    static func slotIndex(containing point: CGPoint, frames: [Int: CGRect]) -> Int? {
        frames.first { $0.value.contains(point) }?.key
    }

    /// Fraction of a slot's area covered by `offer` (sprite + coin + price).
    static func slotCoverage(of offer: CGRect, onto slot: CGRect) -> CGFloat {
        let inter = offer.intersection(slot)
        guard !inter.isNull, inter.width > 0, inter.height > 0 else { return 0 }
        let slotArea = slot.width * slot.height
        guard slotArea > 0 else { return 0 }
        return (inter.width * inter.height) / slotArea
    }

    /// Slot whose area is covered enough by the dragged offer to count as a drop.
    /// `0.40` means a clear overlap, not a glancing coin/price nick.
    static let assistCoverage: CGFloat = 0.40

    static func assistedSlotIndex(
        offer: CGRect,
        frames: [Int: CGRect],
        minimumCoverage: CGFloat = assistCoverage
    ) -> Int? {
        var bestIndex: Int?
        var bestCoverage: CGFloat = 0
        for (index, slot) in frames {
            let coverage = slotCoverage(of: offer, onto: slot)
            guard coverage >= minimumCoverage else { continue }
            if coverage > bestCoverage || (coverage == bestCoverage && index < (bestIndex ?? index)) {
                bestIndex = index
                bestCoverage = coverage
            }
        }
        return bestIndex
    }
}
