import SwiftUI

struct DestructibleWallResultOverlay: View {
    enum Kind {
        case destroyed(starsAwarded: Int)
        case timesUp
    }

    let kind: Kind
    let onFinished: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onFinished() }

            VStack(spacing: 28) {
                Text(title)
                    .font(.system(size: 36, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .accessibilityIdentifier(titleAccessibilityID)

                if case let .destroyed(starsAwarded) = kind, starsAwarded > 0 {
                    HStack(spacing: 16) {
                        ForEach(0..<starsAwarded, id: \.self) { _ in
                            Image(systemName: "star.fill")
                                .font(.system(size: 54))
                                .foregroundStyle(.yellow)
                        }
                    }
                    .accessibilityIdentifier("destructible_wall.result.destroyed.stars")
                }
            }
        }
        .accessibilityIdentifier(rootAccessibilityID)
    }

    private var title: String {
        switch kind {
        case .destroyed: return "The wall is destroyed!"
        case .timesUp: return "times up!"
        }
    }

    private var titleAccessibilityID: String {
        switch kind {
        case .destroyed: return "destructible_wall.result.destroyed.title"
        case .timesUp: return "destructible_wall.result.timesUp.title"
        }
    }

    private var rootAccessibilityID: String {
        switch kind {
        case .destroyed: return "destructible_wall.result.destroyed.root"
        case .timesUp: return "destructible_wall.result.timesUp.root"
        }
    }
}
