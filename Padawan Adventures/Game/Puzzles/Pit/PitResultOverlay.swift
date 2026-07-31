import SwiftUI

struct PitResultOverlay: View {
    enum Kind {
        case escaped(word: String, starsAwarded: Int)
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
            Text(
                "you escaped the pit by spelling \(Text(word.lowercased()).foregroundStyle(.red))!"
            )
            .font(AppFont.swiftUI(size: 36, weight: .bold))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .appCopyShadow()
        }
    }

    private var titleAccessibilityID: String {
        switch kind {
        case .escaped: return "pit.result.escaped.title"
        }
    }

    private var rootAccessibilityID: String {
        switch kind {
        case .escaped: return "pit.result.escaped.root"
        }
    }
}
