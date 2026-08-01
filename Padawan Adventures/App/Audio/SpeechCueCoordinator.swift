import Foundation

/// Re-arms music or ambience ducking while speech / phonics cues are in flight.
@MainActor
final class SpeechCueCoordinator {
    private var duckTask: Task<Void, Never>?

    struct DuckPolicy {
        let holdDuration: TimeInterval
        let rearmInterval: TimeInterval
        let applyHold: (TimeInterval) -> Void
    }

    func startRefreshing(with policy: DuckPolicy) {
        duckTask?.cancel()
        duckTask = Task { @MainActor in
            while !Task.isCancelled {
                policy.applyHold(policy.holdDuration)
                try? await Task.sleep(
                    nanoseconds: UInt64(policy.rearmInterval * 1_000_000_000)
                )
            }
        }
    }

    func stop() {
        duckTask?.cancel()
        duckTask = nil
    }
}
