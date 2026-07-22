@preconcurrency import AVFoundation
import Foundation

nonisolated protocol FrontCameraAvailability: Sendable {
    var isFrontCameraAvailable: Bool { get }
}

nonisolated struct LiveFrontCameraAvailability: FrontCameraAvailability {
    var isFrontCameraAvailable: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil
    }
}

nonisolated struct FixedFrontCameraAvailability: FrontCameraAvailability {
    let isFrontCameraAvailable: Bool
}
