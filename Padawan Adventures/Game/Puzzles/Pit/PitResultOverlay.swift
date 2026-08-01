import SwiftUI

struct PitResultOverlay: View {
    enum Kind {
        case escaped(word: String, starsAwarded: Int)
        case bridged(starsAwarded: Int)
    }

    let kind: Kind
    let onFinished: () -> Void

    var body: some View {
        DismissibleOverlay(accessibilityRootID: rootAccessibilityID, onFinished: onFinished) {
            VStack(spacing: 28) {
                titleView
                    .accessibilityIdentifier(titleAccessibilityID)

                OverlayStars(
                    count: starsAwarded,
                    accessibilityID: starsAccessibilityID
                )
            }
        }
    }

    private var starsAwarded: Int {
        switch kind {
        case let .escaped(_, stars): stars
        case let .bridged(stars): stars
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
        case .bridged:
            Text("you built a bridge across the pit!")
                .font(AppFont.swiftUI(size: 36, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .appCopyShadow()
        }
    }

    private var titleAccessibilityID: String {
        switch kind {
        case .escaped: return "pit.result.escaped.title"
        case .bridged: return "pit.result.bridged.title"
        }
    }

    private var rootAccessibilityID: String {
        switch kind {
        case .escaped: return "pit.result.escaped.root"
        case .bridged: return "pit.result.bridged.root"
        }
    }

    private var starsAccessibilityID: String {
        switch kind {
        case .escaped: return "pit.result.escaped.stars"
        case .bridged: return "pit.result.bridged.stars"
        }
    }
}
