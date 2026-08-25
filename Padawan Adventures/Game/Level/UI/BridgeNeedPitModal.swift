import SwiftUI

struct BridgeNeedPitModal: View {
    let onDismiss: () -> Void

    private static let stringID = "inventory_bridge_need_pit"

    var body: some View {
        ModalOverlayShell(
            accessibilityRootID: "inventory.bridge.needPit",
            onBackgroundTap: onDismiss
        ) {
            ModalCRTPanel {
                ModalCRTText(
                    text: Strings.text(Self.stringID),
                    size: 30,
                    accessibilityID: "inventory.bridge.needPit.message"
                )
            }
            .frame(maxWidth: 520)
            .contentShape(Rectangle())
            .onTapGesture(perform: onDismiss)
        }
        .onAppear { Strings.speak(Self.stringID) }
    }
}
