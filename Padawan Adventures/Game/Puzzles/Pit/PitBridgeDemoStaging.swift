import Foundation

/// The beats `PitBridgeDemoScript` needs from the scene.
@MainActor
protocol PitBridgeDemoStaging: AnyObject {
    /// True when the scene will act on a new gesture right now.
    var demoIsReady: Bool { get }
    /// True once the round is over and only a restart can revive it.
    var demoIsOver: Bool { get }
    var demoWrongMove: MinigameDemoMove? { get }
    var demoCorrectMove: MinigameDemoMove? { get }
    /// Starts a fresh bridge so the demo can loop.
    func demoRestart()
}
