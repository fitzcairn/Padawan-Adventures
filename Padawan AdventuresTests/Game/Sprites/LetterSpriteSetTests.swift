import CoreGraphics
import Foundation
import Testing
@testable import Padawan_Adventures

struct LetterSpriteSetTests {
    private static let allSets = [
        "1-tython", "2-tatooine", "3-ilum", "4-kashyyyk",
        "5-dagobah", "6-coruscant", "7-mustafar", "8-geonosis",
    ]

    @Test func allBundledSetsDecode() throws {
        for name in Self.allSets {
            let set = try LetterSpriteSet.loadFromBundle(set: name)
            #expect(set.meta.letterSet == name)
            #expect(set.frames.count == 52)
            #expect(set.missingKeys.isEmpty, "\(name) missing \(set.missingKeys)")
            for key in LetterSpriteSet.expectedKeys {
                guard let frame = set.frames[key] else {
                    Issue.record("\(name) missing frame \(key)")
                    continue
                }
                #expect(frame.w > 0 && frame.h > 0, "\(name) \(key) size")
            }
        }
    }

    @Test func atlasMetaMatchesSheetSize() throws {
        let set = try LetterSpriteSet.loadFromBundle(set: "1-tython")
        #expect(set.meta.size.w > 0)
        #expect(set.meta.size.h > 0)
        #expect(set.meta.glyphCount == 52 || set.meta.glyphCount == nil)
    }
}
