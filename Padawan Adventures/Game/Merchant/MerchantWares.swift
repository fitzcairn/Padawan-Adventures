import CoreGraphics
import Foundation

/// Selects and lays out merchant wares on the shop mat.
nonisolated enum MerchantWares {
    static let maxCount = 4
    static let diskDiameterFraction: CGFloat = 0.70
    static let maxSpriteFractionOfRadius: CGFloat = 0.80
    static let minGapPoints: CGFloat = 12
    static let minGapSpriteFraction: CGFloat = 0.25

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

    static func disk(in displayedBackground: CGRect) -> (center: CGPoint, radius: CGFloat) {
        let diameter = displayedBackground.height * diskDiameterFraction
        return (CGPoint(x: displayedBackground.midX, y: displayedBackground.midY), diameter / 2)
    }

    static func layout(
        itemIDs: [String],
        diskCenter: CGPoint,
        radius: CGFloat
    ) -> MerchantWaresLayout {
        let n = itemIDs.count
        guard n > 0, radius > 1 else {
            return MerchantWaresLayout(spriteSide: 0, gap: 0, stacks: [])
        }

        var side = radius * maxSpriteFractionOfRadius
        let minSide: CGFloat = 8
        while side > minSide, !fits(count: n, spriteSide: side, radius: radius) {
            side *= 0.92
        }
        if !fits(count: n, spriteSide: side, radius: radius) {
            side = minSide
        }

        let gap = gapWidth(spriteSide: side)
        let stack = stackSize(spriteSide: side)
        let totalWidth = CGFloat(n) * stack.width + CGFloat(max(n - 1, 0)) * gap
        let originX = diskCenter.x - totalWidth / 2
        let originY = diskCenter.y - stack.height / 2

        var stacks: [MerchantWareStackFrame] = []
        stacks.reserveCapacity(n)
        for (index, id) in itemIDs.enumerated() {
            let x = originX + CGFloat(index) * (stack.width + gap)
            stacks.append(
                MerchantWareStackFrame(
                    itemID: id,
                    spriteFrame: CGRect(x: x, y: originY, width: side, height: side),
                    coinFrame: CGRect(
                        x: x + (side - coinSide(spriteSide: side)) / 2,
                        y: originY + side + 4,
                        width: coinSide(spriteSide: side),
                        height: coinSide(spriteSide: side)
                    ),
                    priceFrame: CGRect(
                        x: x,
                        y: originY + side + 4 + coinSide(spriteSide: side) + 4,
                        width: side,
                        height: priceHeight(spriteSide: side)
                    )
                )
            )
        }
        return MerchantWaresLayout(spriteSide: side, gap: gap, stacks: stacks)
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

    static func fits(count: Int, spriteSide: CGFloat, radius: CGFloat) -> Bool {
        guard spriteSide <= radius * maxSpriteFractionOfRadius + 0.01 else { return false }
        let size = stackSize(spriteSide: spriteSide)
        let gap = gapWidth(spriteSide: spriteSide)
        let totalWidth = CGFloat(count) * size.width + CGFloat(max(count - 1, 0)) * gap
        let halfW = totalWidth / 2
        let halfH = size.height / 2
        return hypot(halfW, halfH) <= radius
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
        coins: Int
    ) -> MerchantDropOutcome {
        guard let slotIndex, slots.indices.contains(slotIndex) else {
            return .ignoredOutside
        }
        let occupant = slots[slotIndex]
        if occupant == itemID {
            return .sameItemInSlot
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
}
