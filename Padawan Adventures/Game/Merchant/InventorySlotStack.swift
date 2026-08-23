import SwiftUI

struct InventorySlotFrameKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct InventorySlotStack: View {
    static let useFadeDuration: TimeInterval = 0.4

    let slots: [String]
    let catalog: [String: MerchantItemDefinition]
    let hudHeight: CGFloat
    var interaction: InventorySlotInteraction = .world
    var highlightedIndex: Int? = nil
    var fadingItems: [Int: String] = [:]
    var onTapOccupied: ((Int, String) -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            let layout = InventorySlotLayout.compute(
                hudHeight: hudHeight > 1 ? hudHeight : geo.size.height,
                availableHeight: geo.size.height
            )
            VStack(spacing: layout.gap) {
                ForEach(0..<PlayerGameState.itemSlotCount, id: \.self) { index in
                    slotPlate(index: index, side: layout.side)
                        .frame(width: layout.side, height: layout.side)
                        .background {
                            GeometryReader { slotGeo in
                                Color.clear.preference(
                                    key: InventorySlotFrameKey.self,
                                    value: [index: slotGeo.frame(in: .named("merchantShop"))]
                                )
                            }
                        }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
        }
    }

    @ViewBuilder
    private func slotPlate(index: Int, side: CGFloat) -> some View {
        let live = index < slots.count ? slots[index] : ""
        let fadingID = fadingItems[index]
        let displayID = live.isEmpty ? (fadingID ?? "") : live
        let occupied = !displayID.isEmpty
        let isFadingOut = fadingID != nil
        let highlighted = highlightedIndex == index
        StarWarsConsoleFrame(showsScanlines: occupied && !isFadingOut) {
            ZStack {
                Color.black.opacity(0.92)
                if occupied, let item = catalog[displayID] {
                    MerchantWareSpriteView(itemID: displayID, sprite: item.sprite)
                        .padding(side * 0.12)
                        .opacity(isFadingOut ? 0 : 1)
                }
            }
        }
        .animation(.easeOut(duration: Self.useFadeDuration), value: isFadingOut)
        .overlay {
            if highlighted {
                RoundedRectangle(cornerRadius: side * 0.16, style: .continuous)
                    .stroke(StarWarsConsolePalette.crtBlue, lineWidth: 3)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard interaction == .world, occupied, !isFadingOut else { return }
            onTapOccupied?(index, displayID)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(occupied && !isFadingOut ? displayID : "empty")
        .accessibilityIdentifier("hud.inventory.slot.\(index)")
    }
}
