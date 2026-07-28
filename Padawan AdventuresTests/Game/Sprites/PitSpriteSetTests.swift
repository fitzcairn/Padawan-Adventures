import CoreGraphics
import Foundation
import Testing
@testable import Padawan_Adventures

struct PitSpriteSetTests {
    private static let allSets = [
        "1-tython", "2-tatooine", "3-ilum", "4-kashyyyk",
        "5-dagobah", "6-coruscant", "7-mustafar", "8-geonosis",
    ]

    @Test func allBundledSetsDecode() throws {
        for name in Self.allSets {
            let set = try PitSpriteSet.loadFromBundle(set: name)
            #expect(set.meta.pitSet == name)
            #expect(!set.frames.isEmpty, "\(name) has no tiles")
            #expect(set.tileIDs.count == set.frames.count)
            for key in set.tileIDs {
                guard let frame = set.frames[key] else {
                    Issue.record("\(name) missing frame \(key)")
                    continue
                }
                #expect(frame.w > 0 && frame.h > 0, "\(name) \(key) size")
            }
        }
    }

    @Test func atlasMetaMatchesSheetSize() throws {
        let set = try PitSpriteSet.loadFromBundle(set: "1-tython")
        #expect(set.meta.size.w > 0)
        #expect(set.meta.size.h > 0)
        #expect((set.meta.tileCount ?? set.frames.count) == set.frames.count)
    }
}
