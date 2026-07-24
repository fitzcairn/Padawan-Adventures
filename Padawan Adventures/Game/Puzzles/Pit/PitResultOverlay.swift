import SwiftUI

struct PitResultOverlay: View {
    enum Kind {
        case escaped(word: String, starsAwarded: Int)
        case falling
    }

    let kind: Kind
    let onFinished: () -> Void

    var body: some View {
        DismissibleOverlay(accessibilityRootID: rootAccessibilityID, onFinished: onFinished) {
            VStack(spacing: 28) {
                titleView
                    .accessibilityIdentifier(titleAccessibilityID)

                if case let .escaped(_, starsAwarded) = kind {
                    OverlayStars(
                        count: starsAwarded,
                        accessibilityID: "pit.result.escaped.stars"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var titleView: some View {
        switch kind {
        case let .escaped(word, _):
            (
                Text("you escaped the pit by spelling ")
                    .foregroundStyle(.white)
                + Text(word.lowercased())
                    .foregroundStyle(.red)
                + Text("!")
                    .foregroundStyle(.white)
            )
            .font(.system(size: 36, weight: .bold))
            .multilineTextAlignment(.center)
        case .falling:
            Text("you're fallllling!")
                .font(.system(size: 36, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
        }
    }

    private var titleAccessibilityID: String {
        switch kind {
        case .escaped: return "pit.result.escaped.title"
        case .falling: return "pit.result.falling.title"
        }
    }

    private var rootAccessibilityID: String {
        switch kind {
        case .escaped: return "pit.result.escaped.root"
        case .falling: return "pit.result.falling.root"
        }
    }
}
