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

    /// The 6-coruscant and 7-mustafar blast doors are drawn oversized for their canvases,
    /// so they bake at a reduced footprint width to stand as tall as the rest of the pack.
    @Test func onlyOversizedSetsNarrowTheirFootprint() throws {
        let narrowed: Set<String> = ["6-coruscant", "7-mustafar"]
        for name in Self.allSets {
            let set = try GateSpriteSet.loadFromBundle(set: name)
            #expect(set.footprintScreenWidths == (narrowed.contains(name) ? 1.2 : 1.5), "\(name)")
        }
    }

    /// A 2-tile strip's floor diamonds meet at a south tip two thirds across their bounding
    /// box, so a gate anchored at bottom-center slides up the strip and off the floor.
    @Test func framesAnchorOnTheirGroundTipNotTheirCenter() throws {
        for name in Self.allSets {
            let set = try GateSpriteSet.loadFromBundle(set: name)
            for axis in GateSpriteSet.Axis.allCases {
                guard let frame = set.frame(for: axis), let anchor = frame.anchor else {
                    continue
                }
                let fraction = anchor.x / CGFloat(frame.w)
                #expect(anchor.y == CGFloat(frame.h), "\(name) \(axis.rawValue) anchor.y")
                #expect(
                    axis == .alongX ? fraction > 0.55 : fraction < 0.45,
                    "\(name) \(axis.rawValue) anchor at \(fraction) of the frame"
                )
            }
        }
    }
}
