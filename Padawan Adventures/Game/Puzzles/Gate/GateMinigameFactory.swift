import SwiftUI

enum GateMinigameFactory {
    @MainActor @ViewBuilder
    static func makeView(
        config: GateMinigameConfig,
        playerFx: SoundEffectTable,
        hudConfig: HudConfig,
        letterSpriteSetLibrary: LetterSpriteSetLibrary,
        onFinished: @escaping (GateOutcome) -> Void
    ) -> some View {
        switch config {
        case .spelling(let spelling):
            GateMinigameView(
                puzzleConfig: spelling,
                playerFx: playerFx,
                hudConfig: hudConfig,
                letterSpriteSetLibrary: letterSpriteSetLibrary,
                onFinished: onFinished
            )
        case .letterMatch(let letterMatch):
            GateLetterMatchMinigameView(
                puzzleConfig: letterMatch,
                playerFx: playerFx,
                hudConfig: hudConfig,
                letterSpriteSetLibrary: letterSpriteSetLibrary,
                onFinished: onFinished
            )
        }
    }
}
