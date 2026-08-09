import SwiftUI
import UIKit

/// Full-screen campaign victory: black scrim with artifacts kept visible, then
/// "Congratulations!" / "tap to play more". Dismisses only on tap (no auto-dismiss).
struct CampaignWinOverlay<Artifacts: View>: View {
    let spriteLibrary: SpriteLibrary
    let scrimOpacity: Double
    let textOpacity: Double
    let isInteractive: Bool
    let onFinished: () -> Void
    @ViewBuilder private let artifacts: () -> Artifacts

    @State private var kamFrames: [(image: UIImage, duration: TimeInterval)] = []
    @State private var yodaFrames: [(image: UIImage, duration: TimeInterval)] = []
    @State private var kamOpacity: Double = 0
    @State private var yodaOpacity: Double = 0
    @State private var didReleaseSprites = false

    private var artFadeSeconds: TimeInterval { 0.45 }

    init(
        spriteLibrary: SpriteLibrary,
        scrimOpacity: Double,
        textOpacity: Double,
        isInteractive: Bool,
        onFinished: @escaping () -> Void,
        @ViewBuilder artifacts: @escaping () -> Artifacts
    ) {
        self.spriteLibrary = spriteLibrary
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

            GeometryReader { geo in
                ZStack {
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
                            // Nudge below true center so the lifted artifact rack has room above.
                            .offset(y: geo.size.height * 0.10)

                        Spacer(minLength: 0)

                        Text(Strings.text("campaign_win_tap_to_play_more"))
                            .font(AppFont.swiftUI(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .appCopyShadow()
                            .accessibilityIdentifier("campaignWin.tapHint")
                    }
                    .opacity(textOpacity)
                    .allowsHitTesting(false)
                    .padding(.bottom, 16)
                    .appScreenContentPadding()

                    HStack(alignment: .bottom) {
                        if !kamFrames.isEmpty {
                            AnimatedUIImageView(frames: kamFrames)
                                .frame(height: 200)
                                .opacity(kamOpacity * textOpacity)
                                .accessibilityIdentifier("campaignWin.kam")
                        }
                        Spacer(minLength: 0)
                        if !yodaFrames.isEmpty {
                            AnimatedUIImageView(frames: yodaFrames)
                                .frame(height: 140) // Match loading screen: 30% smaller than kam
                                .offset(x: -geo.size.width * 0.05)
                                .opacity(yodaOpacity * textOpacity)
                                .accessibilityIdentifier("campaignWin.yoda")
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard isInteractive else { return }
            playMenuSound("button_click")
            onFinished()
        }
        .task {
            await loadCharacters()
        }
        .onDisappear {
            releaseSprites()
        }
        .accessibilityIdentifier("campaignWin.root")
    }

    @MainActor
    private func loadCharacters() async {
        guard let config = try? LoadingSpritesConfig.loadFromBundle() else { return }
        for entry in config.entries where entry.id == "kam" || entry.id == "yoda" {
            await spriteLibrary.ensureLoaded(entry.config, id: entry.id)
            revealCharacter(id: entry.id)
            await Task.yield()
        }
    }

    @MainActor
    private func revealCharacter(id: String) {
        switch id {
        case "kam":
            kamFrames = spriteLibrary.uiImages(id: "kam") ?? []
            guard !kamFrames.isEmpty else { return }
            spriteLibrary.releaseTextures(id: "kam")
            withAnimation(.easeIn(duration: artFadeSeconds)) {
                kamOpacity = 1
            }
        case "yoda":
            yodaFrames = spriteLibrary.uiImages(id: "yoda") ?? []
            guard !yodaFrames.isEmpty else { return }
            spriteLibrary.releaseTextures(id: "yoda")
            withAnimation(.easeIn(duration: artFadeSeconds)) {
                yodaOpacity = 1
            }
        default:
            break
        }
    }

    @MainActor
    private func releaseSprites() {
        guard !didReleaseSprites else { return }
        didReleaseSprites = true
        kamFrames = []
        yodaFrames = []
        spriteLibrary.invalidate(id: "kam")
        spriteLibrary.invalidate(id: "yoda")
        MemoryProbe.mark("campaign-win-sprites-released")
    }
}
