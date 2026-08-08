import CoreGraphics
import Testing
@testable import Padawan_Adventures

struct CombatDeflectOrbWordTests {
    @Test func maskedUnitsStartingSingleLetter() {
        #expect(
            CombatDeflectOrbWord.maskedUnits(word: "cat", grapheme: "c", position: .starting)
                == ["_", "a", "t"]
        )
    }

    @Test func maskedUnitsEndingSingleLetter() {
        #expect(
            CombatDeflectOrbWord.maskedUnits(word: "cat", grapheme: "t", position: .ending)
                == ["c", "a", "_"]
        )
    }

    @Test func maskedUnitsStartingDigraph() {
        #expect(
            CombatDeflectOrbWord.maskedUnits(word: "shop", grapheme: "sh", position: .starting)
                == ["_", "_", "o", "p"]
        )
    }

    @Test func maskedUnitsFallsBackWhenGraphemeLongerThanWord() {
        #expect(
            CombatDeflectOrbWord.maskedUnits(word: "cat", grapheme: "cats", position: .starting)
                == ["c", "a", "t"]
        )
    }

    @Test func fitShortWordKeepsBaseWidth() {
        let result = CombatDeflectOrbWord.fit(
            wordWidth: 40,
            baseWidth: 100,
            maxWidth: 200,
            fitFraction: 0.62
        )
        #expect(result.projectileWidth == 100)
        #expect(result.wordScale == 1)
    }

    @Test func fitLongWordGrowsProjectile() {
        let result = CombatDeflectOrbWord.fit(
            wordWidth: 80,
            baseWidth: 100,
            maxWidth: 200,
            fitFraction: 0.62
        )
        let expected = 80 / 0.62
        #expect(abs(result.projectileWidth - expected) < 0.001)
        #expect(result.wordScale == 1)
    }

    @Test func fitOverlongWordClampsAndScalesDown() {
        let result = CombatDeflectOrbWord.fit(
            wordWidth: 200,
            baseWidth: 100,
            maxWidth: 150,
            fitFraction: 0.62
        )
        #expect(result.projectileWidth == 150)
        #expect(result.wordScale < 1)
        #expect(abs(200 * result.wordScale - 150 * 0.62) < 0.001)
    }
}
