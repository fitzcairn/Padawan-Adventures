@preconcurrency import AVFoundation
import SwiftUI
import UIKit

/// Front-camera live preview with photo capture.
@MainActor
final class FrontCameraController: NSObject {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var photoContinuation: CheckedContinuation<UIImage, Error>?
    private(set) var cameraDevice: AVCaptureDevice?
    private(set) var isConfigured = false
    /// Preview layer used so capture rotation matches what the user sees.
    weak var previewLayer: AVCaptureVideoPreviewLayer?

    enum CameraError: Error {
        case unavailable
        case notAuthorized
        case captureFailed
    }

    func prepare() async throws {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            break
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else { throw CameraError.notAuthorized }
        default:
            throw CameraError.notAuthorized
        }

        guard !isConfigured else {
            applyRotationToConnections()
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .photo

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            session.commitConfiguration()
            throw CameraError.unavailable
        }
        cameraDevice = device
        session.addInput(input)

        guard session.canAddOutput(photoOutput) else {
            session.commitConfiguration()
            throw CameraError.unavailable
        }
        session.addOutput(photoOutput)

        session.commitConfiguration()
        isConfigured = true
        applyRotationToConnections()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            // AVCaptureSession is thread-safe for start/stop; not Sendable in the SDK.
            nonisolated(unsafe) let captureSession = session
            DispatchQueue.global(qos: .userInitiated).async {
                captureSession.startRunning()
                continuation.resume()
            }
        }
    }

    func stop() {
        guard session.isRunning else { return }
        nonisolated(unsafe) let captureSession = session
        DispatchQueue.global(qos: .userInitiated).async {
            captureSession.stopRunning()
        }
    }

    func capturePhoto() async throws -> UIImage {
        applyRotationToConnections()
        return try await withCheckedThrowingContinuation { continuation in
            self.photoContinuation = continuation
            let settings = AVCapturePhotoSettings()
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func applyRotationToConnections() {
        guard let device = cameraDevice else { return }

        let coordinator = AVCaptureDevice.RotationCoordinator(
            device: device,
            previewLayer: previewLayer
        )

        if let previewConnection = previewLayer?.connection {
            configure(
                connection: previewConnection,
                rotationAngle: coordinator.videoRotationAngleForHorizonLevelPreview
            )
        }

        if let photoConnection = photoOutput.connection(with: .video) {
            configure(
                connection: photoConnection,
                rotationAngle: coordinator.videoRotationAngleForHorizonLevelCapture
            )
        }
    }

    private func configure(connection: AVCaptureConnection, rotationAngle: CGFloat) {
        connection.automaticallyAdjustsVideoMirroring = false
        if connection.isVideoMirroringSupported {
            connection.isVideoMirrored = true
        }
        if connection.isVideoRotationAngleSupported(rotationAngle) {
            connection.videoRotationAngle = rotationAngle
        }
    }
}

extension FrontCameraController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        Task { @MainActor in
            let continuation = photoContinuation
            photoContinuation = nil

            if let error {
                continuation?.resume(throwing: error)
                return
            }
            guard
                let data = photo.fileDataRepresentation(),
                let image = UIImage(data: data)
            else {
                continuation?.resume(throwing: CameraError.captureFailed)
                return
            }
            continuation?.resume(returning: image)
        }
    }
}

struct CameraPreviewView: UIViewRepresentable {
    let controller: FrontCameraController

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.controller = controller
        view.previewLayer.session = controller.session
        view.previewLayer.videoGravity = .resizeAspectFill
        controller.previewLayer = view.previewLayer
        view.beginOrientationUpdates()
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.controller = controller
        uiView.previewLayer.session = controller.session
        controller.previewLayer = uiView.previewLayer
        uiView.applyRotation()
    }

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        weak var controller: FrontCameraController?
        private var orientationObserver: NSObjectProtocol?

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer.frame = bounds
            applyRotation()
        }

        func beginOrientationUpdates() {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            orientationObserver = NotificationCenter.default.addObserver(
                forName: UIDevice.orientationDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.applyRotation()
            }
            applyRotation()
        }

        func applyRotation() {
            controller?.applyRotationToConnections()
        }

        deinit {
            if let orientationObserver {
                NotificationCenter.default.removeObserver(orientationObserver)
            }
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
    }
}
