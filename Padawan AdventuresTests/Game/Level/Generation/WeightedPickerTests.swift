import Testing
@testable import Padawan_Adventures

struct WeightedPickerTests {
    private struct Item {
        var id: String
        var weight: Double
    }

    @Test func bagEqualWeightsYieldEqualCounts() {
        let items = ["a", "b", "c"].map { Item(id: $0, weight: 1) }
        var bag = WeightedPicker.Bag(items, weight: \.weight, value: \.id)
        var rng = SeededGenerator(seed: 7)
        var counts = ["a": 0, "b": 0, "c": 0]
        for _ in 0..<300 {
            let id = bag.next(using: &rng)!
            counts[id, default: 0] += 1
        }
        #expect(counts == ["a": 100, "b": 100, "c": 100])
    }

    @Test func bagProportionalWeightsMatchCopyRatios() {
        let items = [
            Item(id: "a", weight: 2),
            Item(id: "b", weight: 1),
            Item(id: "c", weight: 1),
        ]
        var bag = WeightedPicker.Bag(items, weight: \.weight, value: \.id)
        var rng = SeededGenerator(seed: 11)
        var counts = ["a": 0, "b": 0, "c": 0]
        for _ in 0..<400 {
            let id = bag.next(using: &rng)!
            counts[id, default: 0] += 1
        }
        #expect(counts == ["a": 200, "b": 100, "c": 100])
    }

    @Test func bagOmitsZeroWeightEntries() {
        let items = [
            Item(id: "a", weight: 0),
            Item(id: "b", weight: 1),
            Item(id: "c", weight: 1),
        ]
        var bag = WeightedPicker.Bag(items, weight: \.weight, value: \.id)
        var rng = SeededGenerator(seed: 3)
        var counts = ["a": 0, "b": 0, "c": 0]
        for _ in 0..<200 {
            let id = bag.next(using: &rng)!
            counts[id, default: 0] += 1
        }
        #expect(counts["a"] == 0)
        #expect(counts["b"] == 100)
        #expect(counts["c"] == 100)
    }

    @Test func bagAllZeroWeightsAlwaysDealsTheFirstEntry() {
        let items = [
            Item(id: "a", weight: 0),
            Item(id: "b", weight: 0),
        ]
        var bag = WeightedPicker.Bag(items, weight: \.weight, value: \.id)
        var rng = SeededGenerator(seed: 5)
        for _ in 0..<50 {
            #expect(bag.next(using: &rng) == "a")
        }
    }

    @Test func bagEmptyReturnsNil() {
        var bag = WeightedPicker.Bag([Item](), weight: \.weight, value: \.id)
        var rng = SeededGenerator(seed: 1)
        #expect(bag.next(using: &rng) == nil)
    }

    @Test func pickNeverChoosesZeroWeightWhenAnotherEntryIsLive() {
        let items = [
            Item(id: "a", weight: 0),
            Item(id: "b", weight: 1),
        ]
        var rng = SeededGenerator(seed: 9)
        for _ in 0..<80 {
            #expect(WeightedPicker.pick(from: items, weight: \.weight, using: &rng)?.id == "b")
        }
    }
}
