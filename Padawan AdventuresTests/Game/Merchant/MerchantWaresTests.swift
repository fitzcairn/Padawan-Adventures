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

    @Test func layoutKeepsSpritesInsideDiskWithGap() {
        let radius: CGFloat = 200
        let layout = MerchantWares.layout(
            itemIDs: ["square", "circle", "triangle"],
            diskCenter: CGPoint(x: 400, y: 300),
            radius: radius,
            slotSide: 56
        )
        #expect(layout.stacks.count == 3)
        #expect(layout.spriteSide <= radius * MerchantWares.maxSpriteFractionOfRadius + 0.01)
        #expect(abs(layout.spriteSide - 56) < 0.5)
        for stack in layout.stacks {
            let minDim = min(stack.spriteFrame.width, stack.spriteFrame.height)
            #expect(abs(minDim - layout.spriteSide) < 0.5)
        }
        #expect(layout.gap >= MerchantWares.minGapPoints - 0.01)
        #expect(layout.gap >= layout.spriteSide * MerchantWares.minGapSpriteFraction - 0.01)

        let center = CGPoint(x: 400, y: 300)
        for stack in layout.stacks {
            let bounds = stack.bounds
            for corner in [
                CGPoint(x: bounds.minX, y: bounds.minY),
                CGPoint(x: bounds.maxX, y: bounds.minY),
                CGPoint(x: bounds.minX, y: bounds.maxY),
                CGPoint(x: bounds.maxX, y: bounds.maxY),
            ] {
                let dx = corner.x - center.x
                let dy = corner.y - center.y
                #expect(hypot(dx, dy) <= radius + 0.5)
            }
        }
        if layout.stacks.count >= 2 {
            let a = layout.stacks[0].bounds
            let b = layout.stacks[1].bounds
            let gap = b.minX - a.maxX
            #expect(gap >= layout.gap - 0.5)
        }
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
