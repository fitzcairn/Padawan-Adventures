import SwiftUI

struct JetpackNeedGateModal: View {
    let onDismiss: () -> Void

    private static let stringID = "inventory_jetpack_need_gate"

    var body: some View {
        ModalOverlayShell(
            accessibilityRootID: "inventory.jetpack.needGate",
            onBackgroundTap: onDismiss
        ) {
            ModalCRTPanel {
                ModalCRTText(
                    text: Strings.text(Self.stringID),
                    size: 30,
                    accessibilityID: "inventory.jetpack.needGate.message",
                    speakID: Self.stringID
                )
            }
            .frame(maxWidth: 520)
        }
        .onAppear { Strings.speak(Self.stringID) }
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
    }
}
