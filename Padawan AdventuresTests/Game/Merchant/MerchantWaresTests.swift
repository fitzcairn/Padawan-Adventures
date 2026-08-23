import CoreGraphics
import Foundation
import Testing
@testable import Padawan_Adventures

struct MerchantWaresTests {
    private let catalog: [String: MerchantItemDefinition] = [
        "square": MerchantItemDefinition(
            minLevel: 1, price: 1, description: "merchant_item_square",
            sprite: MerchantSpriteSpec(shape: .square)
        ),
        "circle": MerchantItemDefinition(
            minLevel: 1, price: 2, description: "merchant_item_circle",
            sprite: MerchantSpriteSpec(shape: .circle)
        ),
        "triangle": MerchantItemDefinition(
            minLevel: 1, price: 3, description: "merchant_item_triangle",
            sprite: MerchantSpriteSpec(shape: .triangle)
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
                sprite: MerchantSpriteSpec(shape: .square)
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
            radius: radius
        )
        #expect(layout.stacks.count == 3)
        #expect(layout.spriteSide <= radius * MerchantWares.maxSpriteFractionOfRadius + 0.01)
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
}
