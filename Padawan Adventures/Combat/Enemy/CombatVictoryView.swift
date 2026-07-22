import SwiftUI

struct CombatVictoryView: View {
    let onFinished: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onFinished() }

            Text("You won!")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(.white)
                .accessibilityIdentifier("combat.youWon.title")
        }
        .accessibilityIdentifier("combat.youWon.root")
    }
}
