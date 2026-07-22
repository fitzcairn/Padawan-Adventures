import AVFoundation
import Foundation

protocol FrontCameraAvailability: Sendable {
    var isFrontCameraAvailable: Bool { get }
}

struct LiveFrontCameraAvailability: FrontCameraAvailability {
    var isFrontCameraAvailable: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil
    }
}

struct FixedFrontCameraAvailability: FrontCameraAvailability {
    let isFrontCameraAvailable: Bool
}
