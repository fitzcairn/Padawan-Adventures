import Foundation

struct GridCoord: Hashable, Equatable, Sendable, WorldPersistable {
    var x: Int
    var y: Int
    var story: Int

    static let cardinals: [(dx: Int, dy: Int)] = [
        (0, -1), (1, 0), (0, 1), (-1, 0),
    ]

    static let diagonals: [(dx: Int, dy: Int)] = [
        (-1, -1), (1, -1), (1, 1), (-1, 1),
    ]

    static let directions8: [(dx: Int, dy: Int)] = cardinals + diagonals

    init(x: Int, y: Int, story: Int) {
        self.x = x
        self.y = y
        self.story = story
    }

    func neighbor(dx: Int, dy: Int) -> GridCoord {
        GridCoord(x: x + dx, y: y + dy, story: story)
    }

    func onStory(_ story: Int) -> GridCoord {
        GridCoord(x: x, y: y, story: story)
    }

    private enum CodingKeys: String, CodingKey {
        case x
        case y
        case story
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        x = try container.decode(Int.self, forKey: .x)
        y = try container.decode(Int.self, forKey: .y)
        story = try container.decode(Int.self, forKey: .story)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
        try container.encode(story, forKey: .story)
    }
}
