import SwiftUI

struct CombatVictoryView: View {
    let onFinished: () -> Void

    var body: some View {
        DismissibleOverlay(accessibilityRootID: "combat.youWon.root", onFinished: onFinished) {
            Text("You won!")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(.white)
                .accessibilityIdentifier("combat.youWon.title")
        }
    }
}
