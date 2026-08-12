import Foundation
import SwiftUI
import Testing
@testable import Padawan_Adventures

@MainActor
struct MinigameTutorialVoiceOverTests {
    @Test func continueCueHasCatalogEntryAndBundledClip() {
        let entry = Strings.catalog.entry(MinigameTutorialVoiceOver.continueStringID)
        #expect(entry?.sfx == "sfx_ui_minigame_tutorial_continue")
        let seconds = MinigameTutorialVoiceOver.seconds(
            forStringID: MinigameTutorialVoiceOver.continueStringID
        )
        #expect((seconds ?? 0) > 0)
    }

    @Test func everyMinigameKindLeadsInForItsWholeVoiceOver() {
        let keys = PitMinigameKind.allCases.map(\.rawValue)
            + GateMinigameKind.allCases.map(\.rawValue)
            + CombatMinigameKind.allCases.map(\.rawValue)
        for key in keys {
            let stringID = MinigameTutorialView<EmptyView>.bodyStringID(forKindRawValue: key)
            guard let clipSeconds = MinigameTutorialVoiceOver.seconds(forStringID: stringID) else {
                Issue.record("no tutorial voice-over clip for '\(key)'")
                continue
            }
            let leadIn = MinigameTutorialView<EmptyView>.leadInSeconds(forKindRawValue: key)
            #expect(leadIn >= clipSeconds)
        }
    }

    @Test func unknownKindFallsBackToFixedLeadIn() {
        let leadIn = MinigameTutorialView<EmptyView>.leadInSeconds(
            forKindRawValue: "not-a-minigame"
        )
        #expect(leadIn == MinigameTutorialVoiceOver.fallbackSeconds)
    }
}
