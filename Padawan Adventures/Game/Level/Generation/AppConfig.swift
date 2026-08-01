import CoreGraphics
import Foundation

/// App-level knobs from `Resources/Config/app.yaml` (seed, display, stories, Dad mode).
/// Map size, generation, enemies, floors, and puzzle FX live on `LevelConfig`.
nonisolated struct AppConfig: Codable, Equatable, Sendable {
    var version: Int
    /// Fixed seed for deterministic worlds. `nil` means resolve from the current time at generation.
    var seed: UInt64?
    var world: WorldSize
    var display: DisplayParams
    /// 4-digit password that unlocks Dad mode on the level select screen.
    var dadModePassword: String

    enum CodingKeys: String, CodingKey {
        case version
        case seed
        case world
        case display
        case dadModePassword = "dad_mode_password"
    }

    /// Default Dad mode password when omitted from YAML.
    static let defaultDadModePassword = "1234"

    nonisolated init(
        version: Int,
        seed: UInt64? = nil,
        world: WorldSize = WorldSize(stories: 1),
        display: DisplayParams = .default,
        dadModePassword: String = AppConfig.defaultDadModePassword
    ) {
        self.version = version
        self.seed = seed
        self.world = world
        self.display = display
        self.dadModePassword = dadModePassword
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        seed = try Self.decodeSeed(from: container)
        world = try container.decode(WorldSize.self, forKey: .world)
        display = try container.decodeIfPresent(DisplayParams.self, forKey: .display) ?? .default
        dadModePassword = try Self.decodeDadModePassword(from: container)
    }

    private static func decodeDadModePassword(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> String {
        guard container.contains(.dadModePassword) else {
            return defaultDadModePassword
        }
        if let value = try? container.decode(String.self, forKey: .dadModePassword) {
            return value
        }
        if let value = try? container.decode(Int.self, forKey: .dadModePassword) {
            return String(value)
        }
        throw WorldSeedError.decodeFailed("dad_mode_password must be a string or integer")
    }

    /// Resolves a concrete RNG seed. Time-based seeds use milliseconds since epoch.
    func resolvedSeed(at date: Date = Date()) -> UInt64 {
        if let seed { return seed }
        let millis = date.timeIntervalSince1970 * 1000
        let value = UInt64(millis.rounded(.down))
        return value == 0 ? 1 : value
    }

    private static func decodeSeed(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> UInt64? {
        guard container.contains(.seed) else { return nil }
        if let decodedSeed = try? container.decode(UInt64.self, forKey: .seed) {
            return decodedSeed
        }
        if let decodedSeed = try? container.decode(Int.self, forKey: .seed) {
            return UInt64(decodedSeed)
        }
        let token = try container.decode(String.self, forKey: .seed)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard token == "time" else {
            throw WorldSeedError.decodeFailed("seed must be an integer or \"time\"")
        }
        return nil
    }

    /// Story count for generated worlds (`width` / `height` come from `LevelConfig`).
    nonisolated struct WorldSize: Codable, Equatable, Sendable {
        var stories: Int

        enum CodingKeys: String, CodingKey {
            case stories
        }

        nonisolated init(stories: Int) {
            self.stories = stories
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            stories = try container.decode(Int.self, forKey: .stories)
        }
    }

    /// On-screen isometric tile footprint (zoom) and shared UI display knobs.
    nonisolated struct DisplayParams: Codable, Equatable, Sendable {
        var tileWidth: Int
        var tileHeight: Int
        var wallHeight: Int?
        var storyHeight: Int?
        /// Seconds before overlays auto-dismiss (tap also dismisses). `0` disables auto-dismiss.
        var overlayDismissSeconds: Double

        nonisolated static let `default` = DisplayParams(
            tileWidth: 40,
            tileHeight: 40,
            overlayDismissSeconds: 6
        )

        enum CodingKeys: String, CodingKey {
            case tileWidth = "tile_width"
            case tileHeight = "tile_height"
            case wallHeight = "wall_height"
            case storyHeight = "story_height"
            case overlayDismissSeconds = "overlay_dismiss_seconds"
        }

        nonisolated init(
            tileWidth: Int = 40,
            tileHeight: Int = 40,
            wallHeight: Int? = nil,
            storyHeight: Int? = nil,
            overlayDismissSeconds: Double = 6
        ) {
            self.tileWidth = tileWidth
            self.tileHeight = tileHeight
            self.wallHeight = wallHeight
            self.storyHeight = storyHeight
            self.overlayDismissSeconds = overlayDismissSeconds
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            tileWidth = try container.decodeIfPresent(Int.self, forKey: .tileWidth) ?? 40
            tileHeight = try container.decodeIfPresent(Int.self, forKey: .tileHeight) ?? 40
            wallHeight = try container.decodeIfPresent(Int.self, forKey: .wallHeight)
            storyHeight = try container.decodeIfPresent(Int.self, forKey: .storyHeight)
            overlayDismissSeconds = try container.decodeIfPresent(
                Double.self,
                forKey: .overlayDismissSeconds
            ) ?? 6
        }

        func makeIsometricConfig() -> IsometricConfig {
            let width = CGFloat(max(tileWidth, 1))
            let height = CGFloat(max(tileHeight, 1))
            let wall = CGFloat(wallHeight ?? max(tileWidth, tileHeight))
            let story = CGFloat(storyHeight ?? max(tileWidth, tileHeight))
            return IsometricConfig(
                tileWidth: width,
                tileHeight: height,
                wallHeight: max(wall, 1),
                storyHeight: max(story, 1),
                maxStories: 1
            )
        }
    }

    func validate() throws {
        guard version == 1 else {
            throw WorldSeedError.unsupportedVersion(version)
        }
        guard world.stories == 1 else {
            throw WorldSeedError.invalidStoryCount(world.stories)
        }
        guard display.tileWidth > 0, display.tileHeight > 0 else {
            throw WorldSeedError.invalidTileSize
        }
    }
}

