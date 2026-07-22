import Foundation
import Yams

/// Per-level map size and generation settings loaded from `base_level.yaml` / `Levels/*.yaml`.
nonisolated struct LevelConfig: Codable, Equatable, Sendable {
    var name: String
    var width: Int
    var height: Int
    var algorithm: String
    var roomCount: Int
    var corridorWidth: Int
    var room: WorldSeedConfig.RoomParams
    var pickups: WorldSeedConfig.PickupsSpawnConfig?

    enum CodingKeys: String, CodingKey {
        case name
        case width
        case height
        case algorithm
        case roomCount = "room_count"
        case corridorWidth = "corridor_width"
        case room
        case pickups
    }

    nonisolated static let fallback = LevelConfig(
        name: "Level 1",
        width: 100,
        height: 100,
        algorithm: "rooms_doors",
        roomCount: 100,
        corridorWidth: 2,
        room: .init(
            minRoomSize: 4,
            maxRoomSize: 12,
            pitChance: 0.2,
            pitMeanSize: 2,
            pitMaxSize: 5,
            wallDestructibleChance: 0.8,
            gateChance: 0.5
        ),
        pickups: .init(
            health: .init(spawnChancePerRoom: 0.8),
            energy: .init(spawnChancePerRoom: 0.8)
        )
    )

    nonisolated init(
        name: String,
        width: Int,
        height: Int,
        algorithm: String,
        roomCount: Int,
        corridorWidth: Int,
        room: WorldSeedConfig.RoomParams,
        pickups: WorldSeedConfig.PickupsSpawnConfig? = nil
    ) {
        self.name = name
        self.width = width
        self.height = height
        self.algorithm = algorithm
        self.roomCount = roomCount
        self.corridorWidth = corridorWidth
        self.room = room
        self.pickups = pickups
    }

    var generation: WorldSeedConfig.GenerationParams {
        .init(
            algorithm: algorithm,
            roomCount: roomCount,
            corridorWidth: corridorWidth,
            room: room
        )
    }

    static func loadFromBundle(
        named name: String = "base_level",
        withExtension ext: String = "yaml",
        subdirectory: String? = nil
    ) throws -> LevelConfig {
        let data = try resourceData(named: name, withExtension: ext, subdirectory: subdirectory)
        return try decode(
            from: data,
            parentDataNamed: { parentName in
                // Inherited bases live at the Resources root.
                try resourceData(named: parentName, withExtension: ext, subdirectory: nil)
            }
        )
    }

    /// Decodes YAML, resolving `inherits:` via `parentDataNamed` when provided (or required).
    static func decode(
        from data: Data,
        parentDataNamed: ((String) throws -> Data)? = nil
    ) throws -> LevelConfig {
        do {
            let merged = try resolveInheritance(
                from: data,
                parentDataNamed: parentDataNamed,
                visited: []
            )
            let yaml = try Yams.dump(object: merged)
            return try YAMLDecoder().decode(LevelConfig.self, from: yaml)
        } catch let error as WorldSeedError {
            throw error
        } catch {
            throw WorldSeedError.decodeFailed
        }
    }

    static func decode(from yaml: String) throws -> LevelConfig {
        try decode(from: Data(yaml.utf8))
    }

    /// Test/helper entry that resolves `inherits:` against in-memory parent YAML documents.
    static func decode(
        from yaml: String,
        parents: [String: String]
    ) throws -> LevelConfig {
        try decode(
            from: Data(yaml.utf8),
            parentDataNamed: { name in
                guard let parentYAML = parents[name] else {
                    throw WorldSeedError.missingResource
                }
                return Data(parentYAML.utf8)
            }
        )
    }

    nonisolated static func deepMerge(
        _ base: [String: Any],
        overwriting child: [String: Any]
    ) -> [String: Any] {
        var result = base
        for (key, value) in child {
            if let childDict = asStringKeyedDictionary(value),
               let baseDict = asStringKeyedDictionary(result[key] as Any?) {
                result[key] = deepMerge(baseDict, overwriting: childDict)
            } else {
                result[key] = normalizeYAMLValue(value)
            }
        }
        return result
    }

    private static func resolveInheritance(
        from data: Data,
        parentDataNamed: ((String) throws -> Data)?,
        visited: Set<String>
    ) throws -> [String: Any] {
        guard let text = String(data: data, encoding: .utf8),
              let loaded = try Yams.load(yaml: text),
              let dict = asStringKeyedDictionary(loaded) else {
            throw WorldSeedError.decodeFailed
        }

        var working = dict
        guard let inherits = working["inherits"] as? String else {
            return working
        }

        let parentName = (inherits as NSString).deletingPathExtension
        guard !visited.contains(parentName) else {
            throw WorldSeedError.decodeFailed
        }
        guard let parentDataNamed else {
            throw WorldSeedError.missingResource
        }

        let parentData = try parentDataNamed(parentName)
        let resolvedParent = try resolveInheritance(
            from: parentData,
            parentDataNamed: parentDataNamed,
            visited: visited.union([parentName])
        )

        working.removeValue(forKey: "inherits")
        return deepMerge(resolvedParent, overwriting: working)
    }

    private static func resourceData(
        named name: String,
        withExtension ext: String,
        subdirectory: String?
    ) throws -> Data {
        // Prefer subdirectory when present; fall back to bundle root because Xcode may flatten
        // Resources/Levels/*.yaml into the app bundle root.
        if let subdirectory,
           let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdirectory) {
            return try Data(contentsOf: url)
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            throw WorldSeedError.missingResource
        }
        return try Data(contentsOf: url)
    }

    private static func asStringKeyedDictionary(_ value: Any?) -> [String: Any]? {
        guard let value else { return nil }
        if let dict = value as? [String: Any] {
            return dict.mapValues { normalizeYAMLValue($0) }
        }
        if let dict = value as? NSDictionary {
            var result: [String: Any] = [:]
            for (key, nested) in dict {
                guard let stringKey = key as? String else { continue }
                result[stringKey] = normalizeYAMLValue(nested)
            }
            return result
        }
        return nil
    }

    private static func normalizeYAMLValue(_ value: Any) -> Any {
        if let dict = asStringKeyedDictionary(value) {
            return dict
        }
        if let array = value as? [Any] {
            return array.map { normalizeYAMLValue($0) }
        }
        if let array = value as? NSArray {
            return array.map { normalizeYAMLValue($0) }
        }
        return value
    }
}

/// A playable level discovered from `Resources/Levels/`.
nonisolated struct LevelDescriptor: Equatable, Sendable {
    let resourceName: String
    let displayName: String
}

nonisolated enum LevelCatalog {
    static let subdirectory = "Levels"

    static func loadFromBundle(
        withExtension ext: String = "yaml"
    ) -> [LevelDescriptor] {
        let urls = levelResourceURLs(withExtension: ext)

        return urls.compactMap { url -> LevelDescriptor? in
            let resourceName = url.deletingPathExtension().lastPathComponent
            guard let level = try? LevelConfig.loadFromBundle(
                named: resourceName,
                withExtension: ext,
                subdirectory: subdirectory
            ) else {
                return nil
            }
            return LevelDescriptor(resourceName: resourceName, displayName: level.name)
        }
        .sorted { $0.resourceName < $1.resourceName }
    }

    private static func levelResourceURLs(withExtension ext: String) -> [URL] {
        if let nested = Bundle.main.urls(
            forResourcesWithExtension: ext,
            subdirectory: subdirectory
        ), !nested.isEmpty {
            return nested
        }

        // Flattened bundle layout: keep only playable `level_*.yaml` files at the root.
        let root = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) ?? []
        return root.filter { url in
            url.deletingPathExtension().lastPathComponent.hasPrefix("level_")
        }
    }
}
