import SwiftUI
import UIKit

struct LoadingView: View {
    @Binding var session: AppSession?
    let router: FlowRouter
    @State private var progress: Double = 0
    @State private var isReady = false
    @State private var spriteLibrary = SpriteLibrary()
    @State private var kamFrames: [(image: UIImage, duration: TimeInterval)] = []
    @State private var logoImage: UIImage?
    @State private var yodaFrames: [(image: UIImage, duration: TimeInterval)] = []
    @State private var kamOpacity: Double = 0
    @State private var logoOpacity: Double = 0
    @State private var yodaOpacity: Double = 0

    /// Loading-screen art occupies the first slice of the progress bar.
    private static let artProgressEnd = 0.12
    private static let artFadeSeconds: TimeInterval = 0.45

    var body: some View {
        AppScreen {
            ZStack {
                VStack {
                    if let logoImage {
                        Image(uiImage: logoImage)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(maxWidth: 360)
                            .padding(.top, 12)
                            .opacity(logoOpacity)
                    }
                    Spacer(minLength: 0)
                }

                GeometryReader { geo in
                    HStack(alignment: .bottom) {
                        if !kamFrames.isEmpty {
                            AnimatedUIImageView(frames: kamFrames)
                                .frame(height: 200)
                                .opacity(kamOpacity)
                        }
                        Spacer(minLength: 0)
                        if !yodaFrames.isEmpty {
                            AnimatedUIImageView(frames: yodaFrames)
                                .frame(height: 140) // 30% smaller than kam
                                .offset(x: -geo.size.width * 0.05)
                                .opacity(yodaOpacity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }

                VStack(spacing: 28) {
                    Spacer(minLength: 0)
                    LoadingScreenScaffold(
                        statusText: isReady
                            ? Strings.text("loading_tap_to_start")
                            : Strings.text("loading_loading"),
                        statusAccessibilityID: "loading.status",
                        progress: isReady ? nil : progress,
                        progressAccessibilityID: isReady ? nil : "loading.progress"
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                guard isReady else { return }
                // Drop the 25 MB kam / yoda clips — only this screen animates them.
                // `logo` stays resident for MenuView.
                kamFrames = []
                yodaFrames = []
                spriteLibrary.invalidate(id: "kam")
                spriteLibrary.invalidate(id: "yoda")
                MemoryProbe.mark("loading-art-released")
                router.showPlayerSelect()
            }
        }
        .playScreenMusic("loading")
        .task {
            // Commit the chrome ("Loading..." + bar) before any asset work.
            await Task.yield()

            // Phase 1 — fade each title asset in as soon as it decodes.
            await GameLogger.step(.lifecycle, "bootstrap.titleArt") {
                await loadLoadingSprites()
            }
            progress = Self.artProgressEnd
            await Task.yield()

            // Phase 2 — configs + every other screen / gameplay asset.
            let artEnd = Self.artProgressEnd
            let loaded = await GameLogger.step(.lifecycle, "bootstrap.loadResources") {
                await AppSession.loadResources(
                    spriteLibrary: spriteLibrary,
                    onProgress: { value in
                        progress = artEnd + (1 - artEnd) * value
                    }
                )
            }
            progress = 1
            session = loaded
            isReady = true
            GameLogger.mark(.lifecycle, "bootstrap complete; loading screen ready")

            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            Strings.speak("loading_tap_to_start")
        }
    }

    @MainActor
    private func loadLoadingSprites() async {
        guard let config = try? LoadingSpritesConfig.loadFromBundle() else { return }
        let entries = config.entries
        let total = max(entries.count, 1)
        for (index, entry) in entries.enumerated() {
            await spriteLibrary.ensureLoaded(entry.config, id: entry.id) { local in
                let entryStart = Double(index) / Double(total)
                let entryEnd = Double(index + 1) / Double(total)
                progress = Self.artProgressEnd * LoadProgress.map(local, from: entryStart, to: entryEnd)
            }
            revealLoadingArt(id: entry.id)
            // Let SwiftUI commit the fade before starting the next sheet.
            await Task.yield()
        }
    }

    @MainActor
    private func revealLoadingArt(id: String) {
        switch id {
        case "kam":
            kamFrames = spriteLibrary.uiImages(id: "kam") ?? []
            guard !kamFrames.isEmpty else { return }
            // SwiftUI-only: drop the SKTexture copies now that UIImages are ready.
            spriteLibrary.releaseTextures(id: "kam")
            withAnimation(.easeIn(duration: Self.artFadeSeconds)) {
                kamOpacity = 1
            }
        case "logo":
            logoImage = spriteLibrary.uiImage(id: "logo")
            guard logoImage != nil else { return }
            withAnimation(.easeIn(duration: Self.artFadeSeconds)) {
                logoOpacity = 1
            }
        case "yoda":
            yodaFrames = spriteLibrary.uiImages(id: "yoda") ?? []
            guard !yodaFrames.isEmpty else { return }
            // SwiftUI-only: drop the SKTexture copies now that UIImages are ready.
            spriteLibrary.releaseTextures(id: "yoda")
            withAnimation(.easeIn(duration: Self.artFadeSeconds)) {
                yodaOpacity = 1
            }
        default:
            break
        }
    }
}
