import Foundation
import Testing
@testable import Padawan_Adventures

struct PlayerGameStateStarsTests {
    @Test func resetLevelStarsCurrentKeepsPlaythroughCoins() {
        var state = PlayerGameState(health: 3, energy: 2)
        state.addLevelStar("level_1")
        state.addLevelStar("level_1")
        #expect(state.totalStars == 2)

        state.resetLevelStarsCurrent("level_1")
        #expect(state.totalStars == 2)
        #expect(state.levels["level_1"]?.starsEarned == 0)
    }

    @Test func decodeLiftsLegacyRunCoinsIntoTheWalletOnce() throws {
        var state = PlayerGameState(health: 3, energy: 2, totalStars: 2)
        state.levels["level_1"] = LevelProgress(starsCurrent: 4)
        state.levels["level_2"] = LevelProgress(starsCurrent: 3)

        let decoded = try PropertyListDecoder().decode(
            PlayerGameState.self,
            from: try PropertyListEncoder().encode(state)
        )
        #expect(decoded.totalStars == 7)
        #expect(decoded.levels["level_1"]?.starsCurrent == 0)
        #expect(decoded.levels["level_2"]?.starsCurrent == 0)

        var spent = decoded
        let emptied = spent.spendMerchantCoins("level_1", count: 7)
        #expect(emptied)
        let again = try PropertyListDecoder().decode(
            PlayerGameState.self,
            from: try PropertyListEncoder().encode(spent)
        )
        #expect(again.totalStars == 0)
    }

    @Test func ensureMinimumCoinsRaisesWalletWithoutStacking() {
        var state = PlayerGameState(health: 3, energy: 2, totalStars: 40)
        state.ensureMinimumCoins(1000)
        #expect(state.totalStars == 1000)
        state.ensureMinimumCoins(1000)
        #expect(state.totalStars == 1000)
        state.addLevelStars("level_1", count: 5)
        state.ensureMinimumCoins(1000)
        #expect(state.totalStars == 1005)
    }

    @Test func addLevelStarsAddsCountInOneStep() {
        var state = PlayerGameState(health: 3, energy: 2)
        state.addLevelStars("level_1", count: 10)
        #expect(state.totalStars == 10)

        state.addLevelStars("level_1", count: 0)
        #expect(state.totalStars == 10)
    }

    @Test func finalizeLevelStarsBanksFirstScoreWithoutDoubleCounting() {
        var state = PlayerGameState(health: 3, energy: 2)
        state.addLevelStar("level_1")
        state.addLevelStar("level_1")
        state.addLevelStar("level_1")

        let result = state.finalizeLevelStars("level_1")
        #expect(result.didBeatPrevious == true)
        #expect(result.previousBest == 0)
        #expect(result.newScore == 3)
        #expect(state.levels["level_1"]?.starsEarned == 3)
        #expect(state.totalStars == 3)
    }

    @Test func finalizeLevelStarsDoesNotAddWalletAgainWhenBeatingBest() {
        var state = PlayerGameState(health: 3, energy: 2, totalStars: 8)
        state.levels["level_1"] = LevelProgress(starsEarned: 5)

        let result = state.finalizeLevelStars("level_1")
        #expect(result.didBeatPrevious == true)
        #expect(result.previousBest == 5)
        #expect(result.newScore == 8)
        #expect(state.levels["level_1"]?.starsEarned == 8)
        #expect(state.totalStars == 8)
    }

    @Test func finalizeLevelStarsDoesNotChangeTotalWhenNotBeaten() {
        var state = PlayerGameState(health: 3, energy: 2, totalStars: 7)
        state.levels["level_1"] = LevelProgress(starsEarned: 7)

        let result = state.finalizeLevelStars("level_1")
        #expect(result.didBeatPrevious == false)
        #expect(result.previousBest == 7)
        #expect(result.newScore == 7)
        #expect(state.levels["level_1"]?.starsEarned == 7)
        #expect(state.totalStars == 7)
    }

    @Test func markLevelCompletedAddsArtifactOnce() {
        var state = PlayerGameState(health: 3, energy: 2)
        state.markLevelCompleted("level_1", artifact: "key.fill")
        state.markLevelCompleted("level_1", artifact: "key.fill")
        state.markLevelCompleted("level_2", artifact: "crown.fill")

        #expect(state.levels["level_1"]?.completed == true)
        #expect(state.levels["level_2"]?.completed == true)
        #expect(state.inventory.artifacts == ["key.fill", "crown.fill"])
    }

    @Test func inventoryAddArtifactIgnoresEmptyAndDuplicates() {
        var inventory = PlayerInventory()
        inventory.addArtifact("")
        inventory.addArtifact("key.fill")
        inventory.addArtifact("key.fill")
        inventory.addArtifact("sparkles")

        #expect(inventory.artifacts == ["key.fill", "sparkles"])
    }

    @Test func resetForNewGameClearsProgressAndRestoresVitals() {
        var state = PlayerGameState(health: 1, energy: 1, totalStars: 9)
        state.markLevelCompleted("level_1", artifact: "key.fill")
        state.levels["level_1"]?.starsEarned = 5
        state.levels["level_1"]?.starsCurrent = 2
        state.lastLevelStarted = "level_1"
        state.stats.enemiesKilled = 3

        state.resetForNewGame(health: 5, energy: 4)

        #expect(state.inventory.artifacts.isEmpty)
        #expect(state.totalStars == 0)
        #expect(state.levels.isEmpty)
        #expect(state.lastLevelStarted == nil)
        #expect(state.health == 5)
        #expect(state.energy == 4)
        #expect(state.stats.enemiesKilled == 3)
        #expect(state.itemSlots == PlayerGameState.emptyItemSlots)
    }

    @Test func merchantSpendsFromThePlaythroughWallet() {
        var state = PlayerGameState(health: 3, energy: 2, totalStars: 5)
        state.addLevelStars("level_1", count: 2)
        #expect(state.spendableCoins(for: "level_1") == 7)

        let spent = state.spendMerchantCoins("level_1", count: 6)
        #expect(spent)
        #expect(state.totalStars == 1)
        #expect(state.spendableCoins(for: "level_2") == 1)

        let tooMuch = state.spendMerchantCoins("level_1", count: 2)
        #expect(tooMuch == false)
        #expect(state.totalStars == 1)
    }

    @Test func purchaseMerchantWareSpendsGlobalCoinsOnAnyLevel() {
        var state = PlayerGameState(health: 3, energy: 2, totalStars: 4)
        let bought = state.purchaseMerchantWare(
            resourceName: "level_2", itemID: "square", slot: 0, price: 3, limit: 1
        )
        #expect(bought)
        #expect(state.itemSlotID(at: 0) == "square")
        #expect(state.totalStars == 1)
    }

    @Test func spendLevelStarsFailsWhenShortAndDoesNotClamp() {
        var state = PlayerGameState(health: 3, energy: 2)
        state.addLevelStars("level_1", count: 4)
        let tooExpensive = state.spendLevelStars("level_1", count: 5)
        #expect(tooExpensive == false)
        #expect(state.totalStars == 4)
        let zeroSpend = state.spendLevelStars("level_1", count: 0)
        #expect(zeroSpend == false)
        let spent = state.spendLevelStars("level_1", count: 4)
        #expect(spent)
        #expect(state.totalStars == 0)
    }

    @Test func itemSlotsPadTruncateReplaceAndClearOnNewGame() throws {
        var state = PlayerGameState(health: 3, energy: 2, itemSlots: ["square"])
        #expect(state.itemSlots.count == 3)
        #expect(state.itemSlotID(at: 0) == "square")
        #expect(state.itemSlotID(at: 1) == nil)

        state.setItemSlot(index: 1, itemID: "circle")
        state.setItemSlot(index: 0, itemID: "triangle")
        #expect(state.itemSlotID(at: 0) == "triangle")
        #expect(state.itemSlotID(at: 1) == "circle")

        let data = try PropertyListEncoder().encode(state)
        let decoded = try PropertyListDecoder().decode(PlayerGameState.self, from: data)
        #expect(decoded.itemSlots == ["triangle", "circle", ""])

        state.setItemSlot(index: 0, itemID: nil)
        #expect(state.itemSlotID(at: 0) == nil)
        #expect(state.itemSlotID(at: 1) == "circle")

        state.resetForNewGame(health: 5, energy: 4)
        #expect(state.itemSlots == PlayerGameState.emptyItemSlots)
    }

    @Test func purchaseMerchantWareHonorsInventoryHoldLimit() {
        var state = PlayerGameState(health: 3, energy: 2)
        state.addLevelStars("level_1", count: 10)

        let first = state.purchaseMerchantWare(
            resourceName: "level_1", itemID: "square", slot: 0, price: 1, limit: 1
        )
        #expect(first)
        #expect(state.itemSlotID(at: 0) == "square")
        #expect(state.totalStars == 9)

        let second = state.purchaseMerchantWare(
            resourceName: "level_1", itemID: "square", slot: 1, price: 1, limit: 1
        )
        #expect(second == false)
        #expect(state.itemSlotID(at: 1) == nil)
        #expect(state.totalStars == 9)

        let unlimited = state.purchaseMerchantWare(
            resourceName: "level_1", itemID: "circle", slot: 1, price: 2, limit: 0
        )
        #expect(unlimited)
        #expect(state.itemSlotID(at: 1) == "circle")

        state.resetLevelStarsCurrent("level_1")
        state.addLevelStars("level_1", count: 5)
        #expect(state.itemSlotID(at: 0) == "square")
        let stillBlocked = state.purchaseMerchantWare(
            resourceName: "level_1", itemID: "square", slot: 2, price: 1, limit: 1
        )
        #expect(stillBlocked == false)

        state.setItemSlot(index: 0, itemID: nil)
        let afterUse = state.purchaseMerchantWare(
            resourceName: "level_1", itemID: "square", slot: 0, price: 1, limit: 1
        )
        #expect(afterUse)
        #expect(state.itemSlotID(at: 0) == "square")
    }

    @Test func merchantPurchasesRoundTripInPlayerState() throws {
        var state = PlayerGameState(health: 3, energy: 2)
        state.recordMerchantPurchase("level_1", itemID: "triangle")
        state.recordMerchantPurchase("level_1", itemID: "triangle")
        let data = try PropertyListEncoder().encode(state)
        let decoded = try PropertyListDecoder().decode(PlayerGameState.self, from: data)
        #expect(decoded.merchantPurchaseCount("level_1", itemID: "triangle") == 2)
        #expect(decoded.merchantPurchaseCount("level_1", itemID: "square") == 0)
    }
}
