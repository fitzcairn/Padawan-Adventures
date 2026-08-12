import SwiftUI

enum GateMinigameFactory {
    @MainActor @ViewBuilder
    static func makeView(
        config: GateMinigameConfig,
        playerFx: SoundEffectTable,
        hudConfig: HudConfig,
        vocabularySampler: LevelVocabularySampler? = nil,
        onFinished: @escaping (MinigameOutcome) -> Void
    ) -> some View {
        switch config {
        case .soundOutWord(let soundOutWord):
            GateSoundOutWordMinigameView(
                puzzleConfig: soundOutWord,
                hudConfig: hudConfig,
                vocabularySampler: vocabularySampler,
                onFinished: onFinished
            )
        case .graphemeMatch(let graphemeMatch):
            GateGraphemeMatchMinigameView(
                puzzleConfig: graphemeMatch,
                vocabularySampler: vocabularySampler,
                onFinished: onFinished
            )
        case .wordPlug(let wordPlug):
            GateWordPlugMinigameView(
                puzzleConfig: wordPlug,
                playerFx: playerFx,
                vocabularySampler: vocabularySampler,
                onFinished: onFinished
            )
        }
    }

    @MainActor @ViewBuilder
    static func makeDemoView(
        config: GateMinigameConfig,
        playerFx: SoundEffectTable,
        hudConfig _: HudConfig,
        leadInSeconds: TimeInterval
    ) -> some View {
        switch config {
        case .soundOutWord(let soundOutWord):
            MinigameDemoView(
                make: { size in
                    GateSoundOutWordScene(size: size, puzzleConfig: soundOutWord)
                },
                leadInSeconds: leadInSeconds
            )
        case .graphemeMatch(let graphemeMatch):
            MinigameDemoView(
                make: { size in
                    GateGraphemeMatchScene(size: size, puzzleConfig: graphemeMatch)
                },
                leadInSeconds: leadInSeconds
            )
        case .wordPlug(let wordPlug):
            MinigameDemoView(
                make: { size in
                    GateWordPlugScene(
                        size: size,
                        puzzleConfig: wordPlug,
                        playerFx: playerFx
                    )
                },
                leadInSeconds: leadInSeconds
            )
        }
    }
}
