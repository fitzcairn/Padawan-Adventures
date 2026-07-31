import Foundation
import Yams

nonisolated enum ConfigError: Error, Equatable {
    case missingResource(file: String)
    case decodeFailed(file: String, reason: String)
    case inheritanceCycle(file: String, chain: [String])
    case unknownParent(file: String, parent: String)
}

/// Bundle lookup, `inherits:` / `defaults:` merging, and YAML decode for config resources.
nonisolated enum ConfigStore {
    /// Loads config, trapping in Debug on failure while still returning a safe fallback.
    static func loadOrFallback<T>(
        _ label: String,
        fallback: T,
        load: () throws -> T
    ) -> T {
        do {
            return try load()
        } catch {
            // Logged as well as trapped: release builds silently take the
            // fallback, and that substitution is invisible without this.
            GameLogger.fault(.config, "config '\(label)' failed to load: \(error)")
            assertionFailure("config \(label) failed to load: \(error)")
            return fallback
        }
    }

    static func load<T: Decodable>(
        _ type: T.Type,
        from path: ConfigPath,
        bundle: Bundle = .main
    ) throws -> T {
        let tree = try rawTree(at: path, bundle: bundle)
        do {
            let yaml = try Yams.dump(object: tree)
            return try YAMLDecoder().decode(type, from: yaml)
        } catch let error as ConfigError {
            throw error
        } catch {
            throw ConfigError.decodeFailed(
                file: path.description,
                reason: String(describing: error)
            )
        }
    }

    static func decode<T: Decodable>(_ type: T.Type, yaml: String) throws -> T {
        let tree = try rawTree(
            from: Data(yaml.utf8),
            parentDataNamed: nil,
            fileLabel: "inline"
        )
        do {
            let dumped = try Yams.dump(object: tree)
            return try YAMLDecoder().decode(type, from: dumped)
        } catch let error as ConfigError {
            throw error
        } catch {
            throw ConfigError.decodeFailed(
                file: "inline",
                reason: String(describing: error)
            )
        }
    }

    static func rawTree(
        at path: ConfigPath,
        bundle: Bundle = .main
    ) throws -> [String: Any] {
        let data = try data(at: path, bundle: bundle)
        return try rawTree(
            from: data,
            parentDataNamed: { parentName in
                try self.data(at: .config(parentName), bundle: bundle)
            },
            fileLabel: path.description
        )
    }

    /// For LevelConfig test helpers / custom parent resolution.
    static func rawTree(
        from data: Data,
        parentDataNamed: ((String) throws -> Data)?,
        fileLabel: String
    ) throws -> [String: Any] {
        var tree = try resolveFileInheritance(
            from: data,
            parentDataNamed: parentDataNamed,
            visited: [],
            fileLabel: fileLabel
        )
        tree = try applyDefaults(to: tree)
        tree = try resolveEntryInheritance(in: tree, fileLabel: fileLabel)
        return tree
    }

    static func data(at path: ConfigPath, bundle: Bundle = .main) throws -> Data {
        // Every Config subdirectory is listed in explicitFolders, so a miss is a real error.
        let url: URL?
        if let subdirectory = path.subdirectory {
            url = bundle.url(
                forResource: path.basename,
                withExtension: path.fileExtension,
                subdirectory: subdirectory
            )
        } else {
            url = bundle.url(
                forResource: path.basename,
                withExtension: path.fileExtension
            )
        }
        guard let url else {
            throw ConfigError.missingResource(file: path.description)
        }
        return try Data(contentsOf: url)
    }

    static func deepMerge(
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

    // MARK: - Inheritance / defaults

    private static let nonCollectionKeys: Set<String> = [
        "version",
        "defaults",
        "inherits",
        "sprite",
        "sprites",
        "slash_max_seconds",
        "slash_max_screen_width_fraction",
        "fade_seconds",
        "fx",
    ]

    private static func resolveFileInheritance(
        from data: Data,
        parentDataNamed: ((String) throws -> Data)?,
        visited: [String],
        fileLabel: String
    ) throws -> [String: Any] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw ConfigError.decodeFailed(
                file: fileLabel,
                reason: "YAML is not valid UTF-8"
            )
        }
        guard let loaded = try Yams.load(yaml: text),
              let dict = asStringKeyedDictionary(loaded) else {
            throw ConfigError.decodeFailed(
                file: fileLabel,
                reason: "YAML did not decode to a dictionary"
            )
        }

        var working = dict
        guard let inherits = working["inherits"] as? String else {
            return working
        }

        let parentName = (inherits as NSString).deletingPathExtension
        if visited.contains(parentName) {
            throw ConfigError.inheritanceCycle(
                file: fileLabel,
                chain: visited + [parentName]
            )
        }
        guard let parentDataNamed else {
            throw ConfigError.unknownParent(file: fileLabel, parent: parentName)
        }

        let parentData: Data
        do {
            parentData = try parentDataNamed(parentName)
        } catch ConfigError.missingResource {
            throw ConfigError.unknownParent(file: fileLabel, parent: parentName)
        }

        let resolvedParent = try resolveFileInheritance(
            from: parentData,
            parentDataNamed: parentDataNamed,
            visited: visited + [parentName],
            fileLabel: fileLabel
        )

        working.removeValue(forKey: "inherits")
        return deepMerge(resolvedParent, overwriting: working)
    }

    private static func applyDefaults(to tree: [String: Any]) throws -> [String: Any] {
        guard let defaultsValue = tree["defaults"],
              let defaults = asStringKeyedDictionary(defaultsValue) else {
            return tree
        }
        guard let collectionKey = findCollectionKey(in: tree) else {
            var result = tree
            result.removeValue(forKey: "defaults")
            return result
        }
        guard let collection = asStringKeyedDictionary(tree[collectionKey] as Any?) else {
            var result = tree
            result.removeValue(forKey: "defaults")
            return result
        }

        var mergedCollection: [String: Any] = [:]
        for (entryID, entryValue) in collection {
            if entryValue is NSNull {
                mergedCollection[entryID] = defaults
            } else if let entryDict = asStringKeyedDictionary(entryValue) {
                mergedCollection[entryID] = deepMerge(defaults, overwriting: entryDict)
            } else {
                mergedCollection[entryID] = normalizeYAMLValue(entryValue)
            }
        }

        var result = tree
        result[collectionKey] = mergedCollection
        result.removeValue(forKey: "defaults")
        return result
    }

    private static func resolveEntryInheritance(
        in tree: [String: Any],
        fileLabel: String
    ) throws -> [String: Any] {
        guard let collectionKey = findCollectionKey(in: tree),
              var collection = asStringKeyedDictionary(tree[collectionKey] as Any?) else {
            return tree
        }

        for entryID in Array(collection.keys) {
            collection[entryID] = try resolveEntry(
                entryID,
                in: &collection,
                visiting: [],
                fileLabel: fileLabel
            )
        }

        var result = tree
        result[collectionKey] = collection
        return result
    }

    private static func resolveEntry(
        _ entryID: String,
        in collection: inout [String: Any],
        visiting: [String],
        fileLabel: String
    ) throws -> Any {
        guard let entry = asStringKeyedDictionary(collection[entryID] as Any?) else {
            return collection[entryID] as Any
        }
        guard let parentID = entry["inherits"] as? String else {
            return entry
        }

        if visiting.contains(entryID) {
            throw ConfigError.inheritanceCycle(
                file: fileLabel,
                chain: visiting + [entryID]
            )
        }
        guard collection[parentID] != nil else {
            throw ConfigError.unknownParent(file: fileLabel, parent: parentID)
        }

        let parentResolved = try resolveEntry(
            parentID,
            in: &collection,
            visiting: visiting + [entryID],
            fileLabel: fileLabel
        )
        guard let parentDict = asStringKeyedDictionary(parentResolved) else {
            throw ConfigError.unknownParent(file: fileLabel, parent: parentID)
        }

        var child = entry
        child.removeValue(forKey: "inherits")
        let merged = deepMerge(parentDict, overwriting: child)
        collection[entryID] = merged
        return merged
    }

    /// Finds the single dict-of-dicts collection key under `tree`, if any.
    private static func findCollectionKey(in tree: [String: Any]) -> String? {
        var found: String?
        for (key, value) in tree {
            if nonCollectionKeys.contains(key) { continue }
            guard let dict = asStringKeyedDictionary(value), !dict.isEmpty else { continue }
            let isDictOfDicts = dict.values.allSatisfy { entry in
                entry is NSNull || asStringKeyedDictionary(entry) != nil
            }
            guard isDictOfDicts else { continue }
            if found != nil { return nil }
            found = key
        }
        return found
    }

    /// Shared by domain resolve steps (e.g. enemy `shot_letters`).
    nonisolated static func asStringKeyedDictionary(_ value: Any?) -> [String: Any]? {
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
