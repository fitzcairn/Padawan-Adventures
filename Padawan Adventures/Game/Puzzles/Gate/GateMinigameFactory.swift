import SwiftUI

enum GateMinigameFactory {
    @MainActor @ViewBuilder
    static func makeView(
        config: GateMinigameConfig,
        playerFx: SoundEffectTable,
        hudConfig: HudConfig,
        onFinished: @escaping (MinigameOutcome) -> Void
    ) -> some View {
        switch config {
        case .soundOutWord(let soundOutWord):
            GateSoundOutWordMinigameView(
                puzzleConfig: soundOutWord,
                hudConfig: hudConfig,
                onFinished: onFinished
            )
        case .graphemeMatch(let graphemeMatch):
            GateGraphemeMatchMinigameView(
                puzzleConfig: graphemeMatch,
                onFinished: onFinished
            )
        case .wordPlug(let wordPlug):
            GateWordPlugMinigameView(
                puzzleConfig: wordPlug,
                playerFx: playerFx,
                onFinished: onFinished
            )
        }
    }
}
