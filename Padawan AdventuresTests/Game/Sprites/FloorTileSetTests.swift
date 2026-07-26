import CoreGraphics
import Foundation
import Testing
@testable import Padawan_Adventures

struct FloorTileSetTests {
    private static let allSets = [
        "1-tython", "2-tatooine", "3-ilum", "4-kashyyyk",
        "5-dagobah", "6-coruscant", "7-mustafar", "8-geonosis",
    ]

    @Test func allBundledSetsDecode() throws {
        for name in Self.allSets {
            let set = try FloorTileSet.loadFromBundle(set: name)
            #expect(set.meta.floorSet == name)
            #expect(!set.frames.isEmpty)
            #expect(!set.floorTileIDs.isEmpty, "\(name) has no floor tiles")
            let aspect = set.meta.diamond.w / set.meta.diamond.h
            #expect(aspect >= 1.45 && aspect <= 1.80, "\(name) aspect \(aspect)")
        }
    }

    @Test func framesHaveAnchorsAndFourEdges() throws {
        let set = try FloorTileSet.loadFromBundle(set: "1-tython")
        for (tid, frame) in set.frames {
            #expect(
                frame.anchor.x >= 0 && frame.anchor.x <= CGFloat(frame.w),
                Comment(rawValue: "\(tid) anchor.x=\(frame.anchor.x) w=\(frame.w)")
            )
            #expect(
                frame.anchor.y >= 0 && frame.anchor.y <= CGFloat(frame.h),
                Comment(rawValue: "\(tid) anchor.y=\(frame.anchor.y) h=\(frame.h)")
            )
            for side in FloorTileSet.Side.allCases {
                #expect(
                    frame.edges[side.rawValue] != nil,
                    Comment(rawValue: "\(tid) missing \(side.rawValue)")
                )
            }
            #expect(frame.edges.count == 4, Comment(rawValue: "\(tid) edge count"))
        }
    }

    @Test func matchesAreSymmetric() throws {
        let set = try FloorTileSet.loadFromBundle(set: "7-mustafar")
        for (tid, frame) in set.frames {
            for side in FloorTileSet.Side.allCases {
                let opp = FloorTileSet.opposite(side)
                for other in frame.matches[side.rawValue] ?? [] {
                    let back = set.frames[other]?.matches[opp.rawValue] ?? []
                    #expect(
                        back.contains(tid),
                        Comment(rawValue: "\(tid).\(side) → \(other) not symmetric")
                    )
                }
            }
        }
    }

    @Test func pitSectionIsSelfConsistent() throws {
        let set = try FloorTileSet.loadFromBundle(set: "6-coruscant")
        for (tid, entry) in set.pits.tiles {
            #expect(set.frames[tid]?.role == .pit, Comment(rawValue: tid))
            let key = entry.voidMask.sorted().joined(separator: ",")
            #expect(set.pits.byMask[key]?.contains(tid) == true, Comment(rawValue: tid))
        }
        for (key, ids) in set.pits.byMask {
            for tid in ids {
                #expect(
                    set.pits.tiles[tid] != nil,
                    Comment(rawValue: "\(key) lists unknown \(tid)")
                )
            }
        }
    }

    @Test func pitTilesMatchingFallsBack() throws {
        let set = try FloorTileSet.loadFromBundle(set: "7-mustafar")
        let all = Set(FloorTileSet.Side.allCases)
        let exactOrOverlap = set.pitTiles(matching: all)
        #expect(!exactOrOverlap.isEmpty)
        #expect(exactOrOverlap.allSatisfy { set.frames[$0]?.role == .pit })
    }
}
