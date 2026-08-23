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

    /// Scale so the shorter axis equals `slotSide` (inventory square height).
    static func fittedSize(pixelSize: CGSize, slotSide: CGFloat) -> CGSize {
        let width = max(pixelSize.width, 0.001)
        let height = max(pixelSize.height, 0.001)
        let scale = slotSide / min(width, height)
        return CGSize(width: width * scale, height: height * scale)
    }

    static func layout(
        itemIDs: [String],
        diskCenter: CGPoint,
        radius: CGFloat,
        slotSide: CGFloat,
        pixelSizes: [String: CGSize] = [:]
    ) -> MerchantWaresLayout {
        let n = itemIDs.count
        guard n > 0, radius > 1 else {
            return MerchantWaresLayout(spriteSide: 0, gap: 0, stacks: [])
        }

        var side = min(max(slotSide, 1), radius * maxSpriteFractionOfRadius)
        let minSide: CGFloat = 8
        func sizes(for side: CGFloat) -> [CGSize] {
            itemIDs.map { id in
                fittedSize(pixelSize: pixelSizes[id] ?? CGSize(width: 1, height: 1), slotSide: side)
            }
        }
        while side > minSide, !fits(sizes: sizes(for: side), slotSide: side, radius: radius) {
            side *= 0.92
        }
        if !fits(sizes: sizes(for: side), slotSide: side, radius: radius) {
            side = minSide
        }

        let displaySizes = sizes(for: side)
        let gap = gapWidth(spriteSide: side)
        let maxSpriteHeight = displaySizes.map(\.height).max() ?? side
        let coin = coinSide(spriteSide: side)
        let price = priceHeight(spriteSide: side)
        let stackHeight = maxSpriteHeight + 4 + coin + 4 + price
        let totalWidth = displaySizes.map(\.width).reduce(0, +) + CGFloat(max(n - 1, 0)) * gap
        let originX = diskCenter.x - totalWidth / 2
        let originY = diskCenter.y - stackHeight / 2

        var stacks: [MerchantWareStackFrame] = []
        stacks.reserveCapacity(n)
        var x = originX
        for (index, id) in itemIDs.enumerated() {
            let display = displaySizes[index]
            let spriteY = originY + (maxSpriteHeight - display.height)
            stacks.append(
                MerchantWareStackFrame(
                    itemID: id,
                    spriteFrame: CGRect(x: x, y: spriteY, width: display.width, height: display.height),
                    coinFrame: CGRect(
                        x: x + (display.width - coin) / 2,
                        y: originY + maxSpriteHeight + 4,
                        width: coin,
                        height: coin
                    ),
                    priceFrame: CGRect(
                        x: x,
                        y: originY + maxSpriteHeight + 4 + coin + 4,
                        width: display.width,
                        height: price
                    )
                )
            )
            x += display.width + gap
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

    static func fits(sizes: [CGSize], slotSide: CGFloat, radius: CGFloat) -> Bool {
        guard slotSide <= radius * maxSpriteFractionOfRadius + 0.01 else { return false }
        guard !sizes.isEmpty else { return true }
        let gap = gapWidth(spriteSide: slotSide)
        let totalWidth = sizes.map(\.width).reduce(0, +) + CGFloat(max(sizes.count - 1, 0)) * gap
        let maxSpriteHeight = sizes.map(\.height).max() ?? slotSide
        let stackHeight = maxSpriteHeight + 4 + coinSide(spriteSide: slotSide) + 4
            + priceHeight(spriteSide: slotSide)
        return hypot(totalWidth / 2, stackHeight / 2) <= radius
    }

    static func fits(count: Int, spriteSide: CGFloat, radius: CGFloat) -> Bool {
        let sizes = Array(repeating: CGSize(width: spriteSide, height: spriteSide), count: count)
        return fits(sizes: sizes, slotSide: spriteSide, radius: radius)
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
}
