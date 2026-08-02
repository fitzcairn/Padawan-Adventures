import Testing
@testable import Padawan_Adventures

struct ContinueEligibilityServiceTests {
    @Test func shouldShowContinueRequiresSaveOrCampaignProgress() {
        #expect(
            ContinueEligibilityService.shouldShowContinue(
                hasCompatibleSave: false,
                playerState: nil
            ) == false
        )
        #expect(
            ContinueEligibilityService.shouldShowContinue(
                hasCompatibleSave: true,
                playerState: nil
            )
        )

        var fresh = PlayerGameState(health: 5, energy: 4)
        #expect(
            ContinueEligibilityService.shouldShowContinue(
                hasCompatibleSave: false,
                playerState: fresh
            ) == false
        )

        fresh.markLevelStarted("1-tython")
        #expect(
            ContinueEligibilityService.shouldShowContinue(
                hasCompatibleSave: false,
                playerState: fresh
            )
        )
    }

    @Test func hasCampaignProgressDetectsCompletedLevelsAndArtifacts() {
        var state = PlayerGameState(health: 5, energy: 4)
        #expect(ContinueEligibilityService.hasCampaignProgress(state) == false)

        state.markLevelCompleted("1-tython", artifact: "key.fill")
        #expect(ContinueEligibilityService.hasCampaignProgress(state))

        var starsOnly = PlayerGameState(health: 5, energy: 4, totalStars: 2)
        #expect(ContinueEligibilityService.hasCampaignProgress(starsOnly))
    }

    @Test func continueDestinationPrefersResumeSaveOverLevelSelect() {
        var state = PlayerGameState(health: 5, energy: 4)
        state.markLevelStarted("1-tython")

        #expect(
            ContinueEligibilityService.continueDestination(
                hasCompatibleSave: true,
                playerState: state
            ) == .resumeSave
        )
        #expect(
            ContinueEligibilityService.continueDestination(
                hasCompatibleSave: false,
                playerState: state
            ) == .levelSelect
        )
        #expect(
            ContinueEligibilityService.continueDestination(
                hasCompatibleSave: false,
                playerState: nil
            ) == nil
        )
    }
}
