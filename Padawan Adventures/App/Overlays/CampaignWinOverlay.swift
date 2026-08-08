import SwiftUI

/// Full-screen campaign victory: black scrim with artifacts kept visible, then
/// "Congratulations!" / "tap to play more". Dismisses only on tap (no auto-dismiss).
struct CampaignWinOverlay<Artifacts: View>: View {
    let scrimOpacity: Double
    let textOpacity: Double
    let isInteractive: Bool
    let onFinished: () -> Void
    @ViewBuilder private let artifacts: () -> Artifacts

    init(
        scrimOpacity: Double,
        textOpacity: Double,
        isInteractive: Bool,
        onFinished: @escaping () -> Void,
        @ViewBuilder artifacts: @escaping () -> Artifacts
    ) {
        self.scrimOpacity = scrimOpacity
        self.textOpacity = textOpacity
        self.isInteractive = isInteractive
        self.onFinished = onFinished
        self.artifacts = artifacts
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(scrimOpacity)
                .ignoresSafeArea()

            // Kept in its own layer so congratulations / tap copy never shift the rack.
            artifacts()
                .allowsHitTesting(false)

            VStack(spacing: 12) {
                Spacer(minLength: 0)

                Text(Strings.text("campaign_win_congratulations"))
                    .font(AppFont.swiftUI(size: 44, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .appCopyShadow()
                    .accessibilityIdentifier("campaignWin.title")

                Spacer(minLength: 0)

                Text(Strings.text("campaign_win_tap_to_play_more"))
                    .font(AppFont.swiftUI(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .appCopyShadow()
                    .padding(.bottom, 88)
                    .accessibilityIdentifier("campaignWin.tapHint")
            }
            .opacity(textOpacity)
            .allowsHitTesting(false)
            .appScreenContentPadding()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard isInteractive else { return }
            playMenuSound("button_click")
            onFinished()
        }
        .accessibilityIdentifier("campaignWin.root")
    }
}
