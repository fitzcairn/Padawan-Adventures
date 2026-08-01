import SwiftUI

struct MinigameResultOverlay: View {
    enum Kind {
        case unlocked(starsAwarded: Int)
        case escaped(word: String, starsAwarded: Int)
        case bridged(starsAwarded: Int)
        case combatVictory
    }

    let kind: Kind
    let onFinished: () -> Void

    var body: some View {
        DismissibleOverlay(accessibilityRootID: rootAccessibilityID, onFinished: onFinished) {
            switch kind {
            case .combatVictory:
                Text("You won!")
                    .font(AppFont.swiftUI(size: 44, weight: .bold))
                    .foregroundStyle(.white)
                    .appCopyShadow()
                    .accessibilityIdentifier("combat.youWon.title")
            default:
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
    }

    private var starsAwarded: Int {
        switch kind {
        case let .unlocked(stars): stars
        case let .escaped(_, stars): stars
        case let .bridged(stars): stars
        case .combatVictory: 0
        }
    }

    @ViewBuilder
    private var titleView: some View {
        switch kind {
        case .unlocked:
            Text("The gate is unlocked!")
                .font(AppFont.swiftUI(size: 36, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .appCopyShadow()
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
        case .combatVictory:
            EmptyView()
        }
    }

    private var titleAccessibilityID: String {
        switch kind {
        case .unlocked: return "gate.result.unlocked.title"
        case .escaped: return "pit.result.escaped.title"
        case .bridged: return "pit.result.bridged.title"
        case .combatVictory: return "combat.youWon.title"
        }
    }

    private var rootAccessibilityID: String {
        switch kind {
        case .unlocked: return "gate.result.unlocked.root"
        case .escaped: return "pit.result.escaped.root"
        case .bridged: return "pit.result.bridged.root"
        case .combatVictory: return "combat.youWon.root"
        }
    }

    private var starsAccessibilityID: String {
        switch kind {
        case .unlocked: return "gate.result.unlocked.stars"
        case .escaped: return "pit.result.escaped.stars"
        case .bridged: return "pit.result.bridged.stars"
        case .combatVictory: return ""
        }
    }
}
