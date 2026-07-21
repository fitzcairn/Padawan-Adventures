import Foundation

struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0xDEADBEEF : seed
    }

    mutating func next() -> UInt64 {
        state = 6364136223846793005 &* state &+ 1
        return state
    }
}

extension RandomNumberGenerator {
    mutating func nextInt(upperBound: Int) -> Int {
        guard upperBound > 0 else { return 0 }
        return Int(next() % UInt64(upperBound))
    }

    mutating func nextBool(probability: Double) -> Bool {
        Double(next() % 10_000) / 10_000.0 < probability
    }

    mutating func pick<T>(_ array: [T]) -> T? {
        guard !array.isEmpty else { return nil }
        return array[nextInt(upperBound: array.count)]
    }
}
