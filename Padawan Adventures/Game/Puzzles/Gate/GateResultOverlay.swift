import SwiftUI

struct GateResultOverlay: View {
    enum Kind {
        case unlocked(starsAwarded: Int)
    }

    let kind: Kind
    let onFinished: () -> Void

    var body: some View {
        DismissibleOverlay(accessibilityRootID: rootAccessibilityID, onFinished: onFinished) {
            VStack(spacing: 28) {
                Text(title)
                    .font(AppFont.swiftUI(size: 36, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .appCopyShadow()
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
        }
    }

    private var titleAccessibilityID: String {
        switch kind {
        case .unlocked: return "gate.result.unlocked.title"
        }
    }

    private var rootAccessibilityID: String {
        switch kind {
        case .unlocked: return "gate.result.unlocked.root"
        }
    }
}
