import CoreGraphics
import Foundation
import Testing
@testable import Padawan_Adventures

struct GateSpriteSetTests {
    private static let allSets = [
        "1-tython", "2-tatooine", "3-ilum", "4-kashyyyk",
        "5-dagobah", "6-coruscant", "7-mustafar", "8-geonosis",
    ]

    @Test func allBundledSetsDecode() throws {
        for name in Self.allSets {
            let set = try GateSpriteSet.loadFromBundle(set: name)
            #expect(set.meta.gateSet == name)
            #expect(set.frame(for: .alongX) != nil, "\(name) missing along_x")
            #expect(set.frame(for: .alongY) != nil, "\(name) missing along_y")
            for axis in GateSpriteSet.Axis.allCases {
                guard let frame = set.frame(for: axis) else { continue }
                #expect(frame.w > 0 && frame.h > 0, "\(name) \(axis.rawValue) size")
                #expect((frame.baseW ?? 0) > 0, "\(name) \(axis.rawValue) base_w")
            }
        }
    }

    @Test func atlasMetaMatchesSheetSize() throws {
        let set = try GateSpriteSet.loadFromBundle(set: "1-tython")
        #expect(set.meta.size.w > 0)
        #expect(set.meta.size.h > 0)
        #expect(set.footprintScreenWidths == 1.5)
        #expect((set.meta.frameCount ?? set.frames.count) == 2)
    }

    /// 6-coruscant's blast door is drawn oversized for its canvas, so it bakes at a
    /// reduced footprint width to stand as tall as the rest of the pack.
    @Test func onlyCoruscantNarrowsItsFootprint() throws {
        for name in Self.allSets {
            let set = try GateSpriteSet.loadFromBundle(set: name)
            #expect(set.footprintScreenWidths == (name == "6-coruscant" ? 1.2 : 1.5), "\(name)")
        }
    }
}
