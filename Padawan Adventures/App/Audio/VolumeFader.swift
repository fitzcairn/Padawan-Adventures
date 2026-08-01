import Foundation

/// Stepped volume ramps shared by music, SFX, and cutscene playback.
enum VolumeFader {
    static let stepInterval: TimeInterval = 0.02

    static func stepCount(for duration: TimeInterval) -> Int {
        max(1, Int(duration / stepInterval))
    }

    static func stepDuration(totalDuration: TimeInterval, steps: Int) -> TimeInterval {
        totalDuration / Double(steps)
    }

    /// Linear ramp from `start` to `end` over `duration`, invoking `apply` each step.
    static func linearFade(
        from start: Float,
        to end: Float,
        duration: TimeInterval,
        apply: @escaping (Float) -> Void
    ) async {
        guard duration > 0 else {
            apply(end)
            return
        }
        let steps = stepCount(for: duration)
        let stepDuration = stepDuration(totalDuration: duration, steps: steps)
        let delta = end - start
        for step in 1...steps {
            guard !Task.isCancelled else { return }
            let t = Float(step) / Float(steps)
            apply(start + delta * t)
            let nanos = UInt64(stepDuration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
        }
    }

    /// Multiplicative fade to silence (each step scales volume by remaining fraction).
    static func fadeOutMultiplicative(
        startVolume: Float,
        duration: TimeInterval,
        apply: @escaping (Float) -> Void
    ) async {
        guard duration > 0 else {
            apply(0)
            return
        }
        let steps = stepCount(for: duration)
        let stepDuration = stepDuration(totalDuration: duration, steps: steps)
        for step in 1...steps {
            guard !Task.isCancelled else { return }
            apply(startVolume * Float(steps - step) / Float(steps))
            let nanos = UInt64(stepDuration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
        }
    }
}
