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
        case .spelling(let spelling):
            GateMinigameView(
                puzzleConfig: spelling,
                playerFx: playerFx,
                hudConfig: hudConfig,
                onFinished: onFinished
            )
        case .letterMatch(let letterMatch):
            GateLetterMatchMinigameView(
                puzzleConfig: letterMatch,
                playerFx: playerFx,
                hudConfig: hudConfig,
                onFinished: onFinished
            )
        case .wordPlug(let wordPlug):
            GateWordPlugMinigameView(
                puzzleConfig: wordPlug,
                playerFx: playerFx,
                hudConfig: hudConfig,
                onFinished: onFinished
            )
        }
    }
}
