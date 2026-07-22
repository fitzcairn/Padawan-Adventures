import SwiftUI

@MainActor
@Observable
final class PlayerSelfieModel {
    var isBusy = false
    var errorMessage: String?

    private let session: AppSession
    let camera = FrontCameraController()

    init(session: AppSession) {
        self.session = session
    }

    var playerName: String {
        session.currentPlayerName ?? "Padawan"
    }

    func startCamera() async {
        do {
            try await camera.prepare()
            errorMessage = nil
        } catch {
            errorMessage = "Camera unavailable"
        }
    }

    func stopCamera() {
        camera.stop()
    }

    /// Captures and saves a thumbnail. Returns `true` when an avatar was saved (capture or fallback).
    func click() async -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        defer { isBusy = false }

        guard let name = session.currentPlayerName else { return false }

        if let image = try? await camera.capturePhoto() {
            let previewSide = min(image.size.width, image.size.height)
            let diameter = PlayerAvatarImage.circleDiameter(
                forPreviewSize: CGSize(width: previewSide, height: previewSide)
            )
            let fraction = previewSide > 0 ? diameter / previewSide : nil
            if let data = PlayerAvatarImage.makeThumbnailJPEG(
                from: image,
                circleDiameterRelativeToMinSide: fraction
            ) {
                try? await session.playerStore.saveAvatar(data, for: name)
                return true
            }
        }

        let fallback = await SillyFaceAvatarGenerator.generateJPEG(seedName: name)
        guard !fallback.isEmpty else { return false }
        try? await session.playerStore.saveAvatar(fallback, for: name)
        return true
    }
}

struct PlayerSelfieView: View {
    let session: AppSession
    let router: FlowRouter
    @State private var model: PlayerSelfieModel

    init(session: AppSession, router: FlowRouter) {
        self.session = session
        self.router = router
        _model = State(initialValue: PlayerSelfieModel(session: session))
    }

    var body: some View {
        VStack(spacing: 16) {
            AppTitleText(
                text: "Smile, \(model.playerName)!",
                size: 28,
                weight: .semibold
            )
            .padding(.top, 24)
            .accessibilityIdentifier("playerSelfie.title")

            Spacer(minLength: 0)

            cameraPreview
                .frame(maxWidth: 420, maxHeight: 420)
                .aspectRatio(1, contentMode: .fit)
                .appReadableWidth()

            if let errorMessage = model.errorMessage {
                AppTitleText(
                    text: errorMessage,
                    size: 14,
                    weight: .regular,
                    color: AppChrome.secondaryTextColor
                )
            }

            Spacer(minLength: 0)

            AppLargeButton(
                title: "Click!",
                accessibilityID: "playerSelfie.click"
            ) {
                Task {
                    if await model.click() {
                        router.showMenu()
                    }
                }
            }
            .disabled(model.isBusy)
            .appReadableWidth()
            .padding(.bottom, 24)
        }
        .padding(.horizontal)
        .appScreenBackground()
        .task {
            await model.startCamera()
        }
        .onDisappear {
            model.stopCamera()
        }
    }

    private var cameraPreview: some View {
        GeometryReader { geo in
            let size = geo.size
            let diameter = PlayerAvatarImage.circleDiameter(forPreviewSize: size)

            ZStack {
                CameraPreviewView(session: model.camera.session)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                Circle()
                    .strokeBorder(Color.white.opacity(0.9), lineWidth: 3)
                    .frame(width: diameter, height: diameter)
                    .allowsHitTesting(false)
            }
        }
    }
}
