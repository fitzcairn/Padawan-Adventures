import CoreGraphics
import Foundation

/// A tap the demo performs, plus how long its audio runs.
struct GateSoundOutWordDemoCue {
    let point: CGPoint
    let seconds: TimeInterval
}

/// The beats `GateSoundOutWordDemoScript` needs from the scene.
@MainActor
protocol GateSoundOutWordDemoStaging: AnyObject {
    /// True when the scene will act on a new gesture right now.
    var demoIsReady: Bool { get }
    /// True once the round is over and only a restart can revive it.
    var demoIsOver: Bool { get }
    /// Centre of the picture plate; nil when the word has no illustration.
    var demoPictureTap: CGPoint? { get }
    /// Centre of the word plate.
    var demoWordPlateTap: CGPoint? { get }
    /// Blank capacitors on offer, left to right.
    var demoChoiceTaps: [GateSoundOutWordDemoCue] { get }
    var demoWordCueSeconds: TimeInterval { get }
    var demoLetterNameCueSeconds: TimeInterval { get }
    var demoWrongMove: MinigameDemoMove? { get }
    var demoCorrectMove: MinigameDemoMove? { get }
    /// True once every grapheme of the word is placed.
    var demoIsWordSolved: Bool { get }
    /// Starts a fresh word so the demo can loop.
    func demoRestart()
}
