import CoreHaptics
import UIKit

/// Continuous rumble for the vector flyover, swelling as the kite passes overhead.
@MainActor
enum VectorStrafeHaptics {
    private static var engine: CHHapticEngine?

    static func playFlyover(duration: TimeInterval) {
        stop()
        guard duration > 0 else { return }
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            playImpactFallback(duration: duration)
            return
        }
        do {
            let engine = try CHHapticEngine()
            try engine.start()
            let rumble = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.18),
                ],
                relativeTime: 0,
                duration: duration
            )
            let swell = CHHapticParameterCurve(
                parameterID: .hapticIntensityControl,
                controlPoints: [
                    CHHapticParameterCurve.ControlPoint(relativeTime: 0, value: 0.18),
                    CHHapticParameterCurve.ControlPoint(relativeTime: duration * 0.5, value: 1),
                    CHHapticParameterCurve.ControlPoint(relativeTime: duration, value: 0.06),
                ],
                relativeTime: 0
            )
            let pattern = try CHHapticPattern(events: [rumble], parameterCurves: [swell])
            let player = try engine.makePlayer(with: pattern)
            engine.notifyWhenPlayersFinished { _ in
                Task { @MainActor in Self.engine = nil }
                return .stopEngine
            }
            try player.start(atTime: CHHapticTimeImmediate)
            self.engine = engine
        } catch {
            playImpactFallback(duration: duration)
        }
    }

    static func stop() {
        engine?.stop(completionHandler: nil)
        engine = nil
    }

    private static func playImpactFallback(duration: TimeInterval) {
        let rumble = UIImpactFeedbackGenerator(style: .heavy)
        rumble.prepare()
        Task { @MainActor in
            let step: TimeInterval = 0.08
            let steps = max(1, Int(duration / step))
            for index in 0..<steps {
                if Task.isCancelled { return }
                let t = Double(index) / Double(max(steps - 1, 1))
                rumble.impactOccurred(intensity: CGFloat(sin(t * .pi)))
                try? await Task.sleep(nanoseconds: UInt64(step * 1_000_000_000))
            }
        }
    }
}
