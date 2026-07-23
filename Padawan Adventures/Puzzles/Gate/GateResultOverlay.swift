import SwiftUI

struct GateResultOverlay: View {
    enum Kind {
        case unlocked(starsAwarded: Int)
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

                if case let .unlocked(starsAwarded) = kind {
                    OverlayStars(
                        count: starsAwarded,
                        accessibilityID: "gate.result.unlocked.stars"
                    )
                }
            }
        }
    }

    private var title: String {
        switch kind {
        case .unlocked: return "The gate is unlocked!"
        case .timesUp: return "times up!"
        }
    }

    private var titleAccessibilityID: String {
        switch kind {
        case .unlocked: return "gate.result.unlocked.title"
        case .timesUp: return "gate.result.timesUp.title"
        }
    }

    private var rootAccessibilityID: String {
        switch kind {
        case .unlocked: return "gate.result.unlocked.root"
        case .timesUp: return "gate.result.timesUp.root"
        }
    }
}
