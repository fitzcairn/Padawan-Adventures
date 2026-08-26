import CoreGraphics
import Foundation
import Testing
@testable import Padawan_Adventures

struct MerchantWaresTests {
    private static let stubSprite = SpriteConfig(root: "Sprites/Items/Merchant")

    private let catalog: [String: MerchantItemDefinition] = [
        "square": MerchantItemDefinition(
            minLevel: 1, price: 1, description: "merchant_item_square",
            sprite: stubSprite
        ),
        "circle": MerchantItemDefinition(
            minLevel: 1, price: 2, description: "merchant_item_circle",
            sprite: stubSprite
        ),
        "triangle": MerchantItemDefinition(
            minLevel: 1, price: 3, description: "merchant_item_triangle",
            sprite: stubSprite
        ),
    ]

    @Test func selectsAllMinLevelOneWares() {
        let ids = MerchantWares.selectIDs(catalog: catalog, levelOrder: 1, seed: 99)
        #expect(Set(ids) == Set(catalog.keys))
        #expect(ids.count == 3)
        #expect(ids.count <= MerchantWares.maxCount)
    }

    @Test func guaranteedOverflowTakesSortedPrefix() {
        var big: [String: MerchantItemDefinition] = [:]
        for index in 1...6 {
            let id = "item-\(index)"
            big[id] = MerchantItemDefinition(
                minLevel: 2,
                price: index,
                description: "d",
                sprite: Self.stubSprite
            )
        }
        let ids = MerchantWares.selectIDs(catalog: big, levelOrder: 2, seed: 1)
        #expect(ids == ["item-1", "item-2", "item-3", "item-4"])
    }

    @Test func layoutPlacesStacksOnACenteredGridWithSmallJitter() {
        let play = CGRect(x: 200, y: 100, width: 400, height: 360)
        let ids = ["square", "circle", "triangle"]
        let layout = MerchantWares.layout(
            itemIDs: ids,
            playArea: play,
            slotSide: 56,
            seed: 99
        )
        #expect(layout.stacks.count == 3)
        #expect(abs(layout.spriteSide - 56) < 0.5)
        #expect(layout.gap >= MerchantWares.minGapPoints - 0.01)

        let padded = play.insetBy(dx: -0.5, dy: -0.5)
        let cellSize = CGSize(
            width: layout.stacks.map(\.bounds.width).max() ?? 56,
            height: layout.stacks.map(\.bounds.height).max() ?? 56
        )
        let grid = MerchantWares.gridRect(cellSize: cellSize, in: play, gap: layout.gap)
        #expect(abs(grid.midX - play.midX) < 0.01)
        #expect(abs(grid.midY - play.midY) < 0.01)

        for (index, stack) in layout.stacks.enumerated() {
            let minDim = min(stack.spriteFrame.width, stack.spriteFrame.height)
            #expect(abs(minDim - layout.spriteSide) < 0.5)
            #expect(padded.contains(stack.bounds))
            let cell = MerchantWares.gridCell(
                index: index,
                in: grid,
                gap: layout.gap * MerchantWares.gridScale
            )
            let base = MerchantWares.centeredOrigin(stack: stack.bounds.size, in: cell)
            #expect(abs(stack.bounds.minX - base.x) <= stack.bounds.width * MerchantWares.positionJitterFraction + 0.5)
            #expect(abs(stack.bounds.minY - base.y) <= stack.bounds.height * MerchantWares.positionJitterFraction + 0.5)
        }
        let columns = Set(layout.stacks.map { $0.bounds.midX > play.midX })
        let rows = Set(layout.stacks.map { $0.bounds.midY > play.midY })
        #expect(columns.count == 2)
        #expect(rows.count == 2)
    }

    @Test func layoutIsStableForASeedAndChangesWithAnother() {
        let play = CGRect(x: 0, y: 0, width: 500, height: 400)
        let ids = ["square", "circle", "triangle"]
        let first = MerchantWares.layout(itemIDs: ids, playArea: play, slotSide: 56, seed: 11)
        let again = MerchantWares.layout(itemIDs: ids, playArea: play, slotSide: 56, seed: 11)
        let other = MerchantWares.layout(itemIDs: ids, playArea: play, slotSide: 56, seed: 12)
        #expect(first == again)
        #expect(first.stacks.map(\.bounds) != other.stacks.map(\.bounds))
    }

    @Test func dropOutcomes() {
        let slots = ["square", "", "circle"]
        #expect(
            MerchantPurchase.outcome(
                itemID: "triangle", slotIndex: nil, slots: slots, price: 1, coins: 10
            ) == .ignoredOutside
        )
        #expect(
            MerchantPurchase.outcome(
                itemID: "square", slotIndex: 0, slots: slots, price: 1, coins: 10
            ) == .sameItemInSlot
        )
        #expect(
            MerchantPurchase.outcome(
                itemID: "triangle", slotIndex: 1, slots: slots, price: 5, coins: 2
            ) == .cannotAfford
        )
        #expect(
            MerchantPurchase.outcome(
                itemID: "triangle", slotIndex: 1, slots: slots, price: 2, coins: 2
            ) == .purchaseEmptySlot
        )
        #expect(
            MerchantPurchase.outcome(
                itemID: "triangle", slotIndex: 2, slots: slots, price: 1, coins: 10
            ) == .confirmReplace
        )
        #expect(
            MerchantPurchase.outcome(
                itemID: "square",
                slotIndex: 1,
                slots: slots,
                price: 1,
                coins: 10,
                limit: 1
            ) == .soldOut
        )
        #expect(
            MerchantPurchase.outcome(
                itemID: "triangle",
                slotIndex: 1,
                slots: slots,
                price: 1,
                coins: 10,
                limit: 0
            ) == .purchaseEmptySlot
        )
        #expect(
            MerchantPurchase.outcome(
                itemID: "square",
                slotIndex: 1,
                slots: slots,
                price: 5,
                coins: 2,
                limit: 1
            ) == .soldOut
        )
        #expect(
            MerchantPurchase.outcome(
                itemID: "square",
                slotIndex: 2,
                slots: ["square", "", ""],
                price: 1,
                coins: 10,
                limit: 2
            ) == .purchaseEmptySlot
        )
    }

    @Test func inventorySlotLayoutSpacesSquaresByTenthOfSide() {
        let hud: CGFloat = 400
        let roomy = InventorySlotLayout.compute(hudHeight: hud, availableHeight: 400)
        #expect(abs(roomy.side - 56) < 0.5)
        #expect(abs(roomy.gap - roomy.side * 0.10) < 0.01)
        #expect(abs(roomy.pitch - (roomy.side + roomy.gap)) < 0.01)
        #expect(roomy.clusterHeight < hud)
        let tight = InventorySlotLayout.compute(hudHeight: hud, availableHeight: 80)
        #expect(tight.side < roomy.side)
        #expect(abs(tight.gap - tight.side * 0.10) < 0.01)
    }

    @Test func dragReturnDurationScalesWithTravelThenClamps() {
        #expect(MerchantDragMotion.returnDuration(for: .zero) == 0.22)
        #expect(MerchantDragMotion.returnDuration(for: CGSize(width: 100, height: 0)) == 0.22)
        #expect(
            abs(MerchantDragMotion.returnDuration(for: CGSize(width: 340, height: 0)) - 340 / 850)
                < 0.0001
        )
        #expect(MerchantDragMotion.returnDuration(for: CGSize(width: 2000, height: 0)) == 0.48)
    }

    @Test func layoutKeepsRemainingWaresInPlace() {
        let ids = ["wide-a", "wide-b", "wide-c", "wide-d"]
        let pixels = Dictionary(
            uniqueKeysWithValues: ids.map { ($0, CGSize(width: 200, height: 120)) }
        )
        let play = CGRect(x: 80, y: 40, width: 640, height: 480)
        let slotSide: CGFloat = 56
        let full = MerchantWares.layout(
            itemIDs: ids,
            playArea: play,
            slotSide: slotSide,
            pixelSizes: pixels,
            seed: 3
        )
        let remainingIDs = Array(ids.dropLast())
        let remaining = MerchantWares.layout(
            itemIDs: remainingIDs,
            playArea: play,
            slotSide: slotSide,
            pixelSizes: pixels,
            fitItemIDs: ids,
            seed: 3
        )
        #expect(abs(remaining.spriteSide - full.spriteSide) < 0.01)
        #expect(remaining.stacks.count == remainingIDs.count)
        for stack in remaining.stacks {
            #expect(full.stacks.first(where: { $0.itemID == stack.itemID }) == stack)
        }
    }

    @Test func gridRectIsACenteredTwoByTwo() {
        let play = CGRect(x: 0, y: 0, width: 800, height: 600)
        let grid = MerchantWares.gridRect(
            cellSize: CGSize(width: 90, height: 120),
            in: play,
            gap: 14
        )
        #expect(abs(grid.midX - play.midX) < 0.01)
        #expect(abs(grid.midY - play.midY) < 0.01)
        #expect(abs(grid.width - (90 * 2 + 14) * MerchantWares.gridScale) < 0.01)
        #expect(abs(grid.height - (120 * 2 + 14) * MerchantWares.gridScale) < 0.01)
        #expect(play.contains(grid))
        let cellGap = 14 * MerchantWares.gridScale
        let topLeft = MerchantWares.gridCell(index: 0, in: grid, gap: cellGap)
        let topRight = MerchantWares.gridCell(index: 1, in: grid, gap: cellGap)
        let bottomLeft = MerchantWares.gridCell(index: 2, in: grid, gap: cellGap)
        #expect(topLeft.maxX <= topRight.minX + 0.01)
        #expect(topLeft.maxY <= bottomLeft.minY + 0.01)
    }

    @Test func playAreaIsCenteredOnTheDisplayedBackground() {
        let displayed = CGRect(x: 10, y: 20, width: 1000, height: 500)
        let play = MerchantWares.playArea(in: displayed)
        #expect(abs(play.midX - displayed.midX) < 0.01)
        #expect(abs(play.midY - displayed.midY) < 0.01)
        #expect(abs(play.width - displayed.width * MerchantWares.playWidthFraction) < 0.01)
        #expect(abs(play.height - displayed.height * MerchantWares.playHeightFraction) < 0.01)
    }

    @Test func fittedSizeMatchesShorterAxisToSlotSide() {
        let wide = MerchantWares.fittedSize(pixelSize: CGSize(width: 373, height: 288), slotSide: 56)
        #expect(abs(wide.height - 56) < 0.001)
        #expect(abs(wide.width - 373 * 56 / 288) < 0.001)
        let tall = MerchantWares.fittedSize(pixelSize: CGSize(width: 290, height: 364), slotSide: 56)
        #expect(abs(tall.width - 56) < 0.001)
        #expect(abs(tall.height - 364 * 56 / 290) < 0.001)
        let square = MerchantWares.fittedSize(pixelSize: CGSize(width: 100, height: 100), slotSide: 56)
        #expect(abs(square.width - 56) < 0.001)
        #expect(abs(square.height - 56) < 0.001)
    }

    @Test func assistedSlotRequiresSignificantOverlap() {
        let slots: [Int: CGRect] = [
            0: CGRect(x: 0, y: 0, width: 100, height: 100),
            1: CGRect(x: 0, y: 110, width: 100, height: 100),
        ]
        #expect(
            MerchantPurchase.assistedSlotIndex(
                offer: CGRect(x: 400, y: 400, width: 80, height: 160),
                frames: slots
            ) == nil
        )
        // 10% of slot 0.
        #expect(
            MerchantPurchase.assistedSlotIndex(
                offer: CGRect(x: 0, y: 0, width: 10, height: 100),
                frames: slots
            ) == nil
        )
        // 50% of slot 0.
        #expect(
            MerchantPurchase.assistedSlotIndex(
                offer: CGRect(x: 0, y: 0, width: 50, height: 100),
                frames: slots
            ) == 0
        )
        // Covers 40% of slot 1 and 80% of slot 0 — pick the greater coverage.
        #expect(
            MerchantPurchase.assistedSlotIndex(
                offer: CGRect(x: 0, y: 0, width: 80, height: 150),
                frames: slots
            ) == 0
        )
        #expect(
            abs(
                MerchantPurchase.slotCoverage(
                    of: CGRect(x: 0, y: 0, width: 40, height: 100),
                    onto: CGRect(x: 0, y: 0, width: 100, height: 100)
                ) - 0.4
            ) < 0.0001
        )
        #expect(
            MerchantPurchase.assistedSlotIndex(
                offer: CGRect(x: 0, y: 0, width: 40, height: 100),
                frames: slots
            ) == 0
        )
    }
}
