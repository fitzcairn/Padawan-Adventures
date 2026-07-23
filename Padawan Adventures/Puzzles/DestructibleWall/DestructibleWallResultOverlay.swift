import SwiftUI

struct DestructibleWallResultOverlay: View {
    enum Kind {
        case destroyed(starsAwarded: Int)
        case timesUp
    }

    let kind: Kind
    let onFinished: () -> Void

    var body: some View {
        DismissibleOverlay(accessibilityRootID: rootAccessibilityID, onFinished: onFinished) {
            VStack(spacing: 28) {
                Text(title)
                    .font(.system(size: 36, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .accessibilityIdentifier(titleAccessibilityID)

                if case let .destroyed(starsAwarded) = kind {
                    OverlayStars(
                        count: starsAwarded,
                        accessibilityID: "destructible_wall.result.destroyed.stars"
                    )
                }
            }
        }
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
