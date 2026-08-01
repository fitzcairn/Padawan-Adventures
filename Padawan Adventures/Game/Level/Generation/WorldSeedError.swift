import CoreGraphics
import Foundation

nonisolated enum WorldSeedError: Error, Equatable {
    case unsupportedVersion(Int)
    case invalidStoryCount(Int)
    case worldTooSmall
    case invalidTileSize
    case corridorTooNarrow(Int)
    case roomTooNarrow(Int)
    case invalidRoomSizeRange
    case invalidRoomPitChance(Double)
    case invalidRoomPitSize(mean: Double, max: Int)
    case invalidRoomPartitionGateChance(Double)
    case invalidGateMinigameChance(Double)
    case invalidGatePaddingLetters(Int)
    case invalidGateWords
    case invalidPitWords
    case invalidPitMinigameWeight(Double)
    case invalidPitBridgeWordRange(min: Int, max: Int)
    case invalidPitBridgeWords
    case invalidLetterSoundRepeat(Double)
    case invalidCombatLetterSpawnRate(Double)
    case invalidCombatLetterCase(String)
    case invalidCombatMinigameWeight(Double)
    case invalidCombatMonsterHP(Int)
    case invalidCombatOrbTravelSeconds(Double)
    case invalidCombatDeflectLetters
    case invalidGateLetterMatchIncorrectReplayDelay(Double)
    case invalidGateLetterMatchLetterCountRange(min: Int, max: Int)
    case invalidGateLetterMatchLetters
    case invalidGateWordPlugWordCountRange(min: Int, max: Int)
    case invalidGateWordPlugLetters
    case invalidEnemyType
    case invalidEnemySpawnChance(Double)
    case invalidPickupSpawnChance(kind: PickupKind, chance: Double)
    /// Generated map is missing one or more required interactables after retries.
    case missingRequiredInteractables([RequiredInteractable])
    case missingResource
    /// YAML/config decode failed; associated value carries the underlying reason.
    case decodeFailed(String)
    case emptyFloorSet
    case emptyLetterSet
    case invalidDecorProb(Double)
    /// Only `rooms_doors` is implemented; other values are rejected at validate time.
    case unsupportedGenerationAlgorithm(String)
}
