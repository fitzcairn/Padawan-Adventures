import CoreGraphics
import Foundation

nonisolated enum WorldSeedError: Error, Equatable {
    case unsupportedVersion(Int)
    case worldTooSmall
    case invalidTileSize
    case roomTooNarrow(Int)
    case invalidRoomSizeRange
    case invalidRoomPitChance(Double)
    case invalidRoomPitSize(mean: Double, max: Int)
    case invalidGateProbability(Double)
    case invalidGateMinigameChance(Double)
    case invalidGateSoundOutWordChoiceRange(min: Int, max: Int)
    case invalidGateSoundOutWordLetters
    case invalidGateWords
    case invalidPitWords
    case invalidPitMinigameWeight(Double)
    case invalidGateMinigameWeight(Double)
    case duplicateGateMinigameKind(GateMinigameKind)
    case invalidPitBridgeWordRange(min: Int, max: Int)
    case invalidPitBridgeWords
    case invalidPitSoundOutWordChoiceRange(min: Int, max: Int)
    case invalidPitSoundOutWordWords
    case invalidPitSoundOutWordGraphemes
    case invalidGraphemeSoundRepeat(Double)
    case invalidCombatGraphemeSpawnRate(Double)
    case invalidCombatGraphemeCase(String)
    case invalidCombatMinigameWeight(Double)
    case invalidCombatMonsterHP(Int)
    case invalidCombatOrbTravelSeconds(Double)
    case invalidCombatDeflectGraphemes
    case invalidGateGraphemeMatchCountRange(min: Int, max: Int)
    case invalidGateGraphemeMatchGraphemes
    case invalidGateWordPlugWordCountRange(min: Int, max: Int)
    case invalidGateWordPlugGraphemes
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
    case invalidFloorCohesion(Double)
}
