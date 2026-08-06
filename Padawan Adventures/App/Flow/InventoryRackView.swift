import SwiftUI
import UIKit

struct InventoryRackView: View {
    let session: AppSession
    let inventoryLevels: [LevelDescriptor]
    let inventoryTreasureIDs: [String]
    let isContentReady: Bool
    let celebratingInventoryResource: String?
    let celebrationRevealed: Bool
    let inventorySparklesActive: Bool

    @Binding var inventoryIcons: [String: UIImage]

    private let inventoryIconSide: CGFloat = 52

    var body: some View {
        HStack(spacing: 16) {
            Spacer(minLength: 0)
            ForEach(inventoryLevels, id: \.resourceName) { level in
                inventoryIcon(for: level)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(height: 72)
        .task(id: inventoryTreasureIDs) {
            guard isContentReady else { return }
            let ids = inventoryTreasureIDs
            await session.ensureTreasureIconsLoaded(ids: ids)
            inventoryIcons = refreshInventoryIcons(ids: ids)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("levelSelect.inventory")
        .accessibilityLabel(Strings.text("level_select_inventory"))
    }

    private func refreshInventoryIcons(ids: [String]) -> [String: UIImage] {
        var icons: [String: UIImage] = [:]
        for id in ids {
            if let image = session.spriteLibrary.uiImage(id: id) {
                icons[id] = image
            }
        }
        return icons
    }

    @ViewBuilder
    private func inventoryIcon(for level: LevelDescriptor) -> some View {
        let isCelebrating = celebratingInventoryResource == level.resourceName
        let opacity: Double = (isCelebrating && !celebrationRevealed) ? 0 : 1
        let sprite = level.treasure.flatMap { inventoryIcons[$0] }
        // Idle twinkle on visible treasure art only; pause during the unlock burst.
        let gleamEnabled = sprite != nil && opacity > 0 && !(isCelebrating && inventorySparklesActive)

        ZStack {
            Group {
                if let id = level.treasure, let image = sprite {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: inventoryIconSide, height: inventoryIconSide)
                        // Parts stand upright in the sheets; lay them flat along the rack.
                        .rotationEffect(.degrees(90))
                        .accessibilityIdentifier("levelSelect.inventory.\(id)")
                        .accessibilityLabel(level.displayName)
                } else {
                    Image(systemName: level.artifact)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(AppChrome.primaryTextColor)
                        .frame(width: inventoryIconSide, height: inventoryIconSide)
                        .accessibilityIdentifier("levelSelect.inventory.\(level.artifact)")
                }

                SpiralGleamView(
                    isEnabled: gleamEnabled,
                    diameter: inventoryIconSide,
                    image: sprite
                )
                .frame(width: inventoryIconSide, height: inventoryIconSide)
                .allowsHitTesting(false)
            }
            // Fade only the icon; keep the burst fully visible around it (same as planet unlock).
            .opacity(opacity)

            if isCelebrating {
                SparkleBurstView(isActive: inventorySparklesActive, diameter: inventoryIconSide)
                    .frame(width: inventoryIconSide, height: inventoryIconSide)
                    .allowsHitTesting(false)
            }
        }
    }
}
