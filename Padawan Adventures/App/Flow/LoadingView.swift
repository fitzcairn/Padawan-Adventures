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
                    }
                    Spacer(minLength: 0)
                }

                GeometryReader { geo in
                    HStack(alignment: .bottom) {
                        if !kamFrames.isEmpty {
                            AnimatedUIImageView(frames: kamFrames)
                                .frame(height: 200)
                        }
                        Spacer(minLength: 0)
                        if !yodaFrames.isEmpty {
                            AnimatedUIImageView(frames: yodaFrames)
                                .frame(height: 140) // 30% smaller than kam
                                .offset(x: -geo.size.width * 0.05)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }

                VStack(spacing: 28) {
                    Spacer(minLength: 0)
                    AppTitleText(
                        text: isReady ? "Tap to start" : "Loading...",
                        size: 32,
                        weight: .semibold
                    )
                    .accessibilityIdentifier("loading.status")

                    if !isReady {
                        AppProgressBar(progress: progress, accessibilityID: "loading.progress")
                            .frame(maxWidth: 280)
                            .appReadableWidth()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                guard isReady else { return }
                router.showPlayerSelect()
            }
        }
        .playScreenMusic("loading")
        .task {
            await loadLoadingSprites()
            let loaded = await AppSession.loadResources { value in
                progress = value
            }
            progress = 1
            session = loaded
            isReady = true
        }
    }

    @MainActor
    private func loadLoadingSprites() async {
        guard let config = try? LoadingSpritesConfig.loadFromBundle() else { return }
        for entry in config.entries {
            await spriteLibrary.ensureLoaded(entry.config, id: entry.id)
        }
        kamFrames = spriteLibrary.uiImages(id: "kam") ?? []
        logoImage = spriteLibrary.uiImage(id: "logo")
        yodaFrames = spriteLibrary.uiImages(id: "yoda") ?? []
    }
}
