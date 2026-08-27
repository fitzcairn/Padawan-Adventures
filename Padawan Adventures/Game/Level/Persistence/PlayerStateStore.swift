import Foundation

nonisolated enum PlayerStateError: Error, Equatable, Sendable {
    case emptyName
    case nameNotUnique
    case playerNotFound
    case corruptData
    case unsupportedVersion(Int)
}

actor PlayerStateStore {
    static let rootFolderName = "PadawanAdventures"
    static let rosterFileName = "players.json"
    static let playersDirectoryName = "players"
    static let stateFileName = "state.plist"
    static let avatarFileName = "avatar.jpg"

    private let fileManager: FileManager
    /// Stable root path; safe to read outside the actor.
    nonisolated let rootDirectoryURL: URL
    private let rosterURL: URL
    private let playersDirectory: URL

    init(fileManager: FileManager = .default, directoryURL: URL? = nil) throws {
        self.fileManager = fileManager

        let rootDirectory: URL
        if let directoryURL {
            rootDirectory = directoryURL
        } else {
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            rootDirectory = appSupport.appendingPathComponent(Self.rootFolderName, isDirectory: true)
        }

        rootDirectoryURL = rootDirectory
        rosterURL = rootDirectory.appendingPathComponent(Self.rosterFileName)
        playersDirectory = rootDirectory.appendingPathComponent(Self.playersDirectoryName, isDirectory: true)

        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: playersDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Roster

    func listPlayers() throws -> [String] {
        try loadRoster()
    }

    func createPlayer(name: String, initialState: PlayerGameState) throws {
        let trimmed = Self.normalizedName(name)
        guard !trimmed.isEmpty else { throw PlayerStateError.emptyName }

        var roster = try loadRoster()
        guard !roster.contains(trimmed) else { throw PlayerStateError.nameNotUnique }

        let directory = playerDirectoryURL(for: trimmed)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try writeState(initialState, for: trimmed)

        roster.append(trimmed)
        try saveRoster(roster)
    }

    func deletePlayer(name: String) throws {
        let trimmed = Self.normalizedName(name)
        var roster = try loadRoster()
        guard let index = roster.firstIndex(of: trimmed) else {
            throw PlayerStateError.playerNotFound
        }

        roster.remove(at: index)
        try saveRoster(roster)

        let directory = playerDirectoryURL(for: trimmed)
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
    }

    // MARK: - Per-player state

    func loadState(for name: String) throws -> PlayerGameState {
        let trimmed = Self.normalizedName(name)
        let url = stateURL(for: trimmed)
        guard fileManager.fileExists(atPath: url.path) else {
            throw PlayerStateError.playerNotFound
        }

        let data = try Data(contentsOf: url)
        return try Self.decodeState(data)
    }

    func saveState(_ state: PlayerGameState, for name: String) throws {
        let trimmed = Self.normalizedName(name)
        let roster = try loadRoster()
        guard roster.contains(trimmed) else {
            throw PlayerStateError.playerNotFound
        }
        try writeState(state, for: trimmed)
    }

    /// Replaces an older/newer save with a blank current-format game, keeping settings when readable.
    func resetIncompatibleState(for name: String, health: Int, energy: Int) throws -> PlayerGameState {
        let trimmed = Self.normalizedName(name)
        let roster = try loadRoster()
        guard roster.contains(trimmed) else {
            throw PlayerStateError.playerNotFound
        }

        let settings: PlayerSettings
        if let data = try? Data(contentsOf: stateURL(for: trimmed)),
           let stale = try? PropertyListDecoder().decode(PlayerGameState.self, from: data) {
            settings = stale.settings
        } else {
            settings = .default
        }

        let fresh = PlayerGameState(health: health, energy: energy, settings: settings)
        try writeState(fresh, for: trimmed)
        return fresh
    }

    func playerDirectoryURL(for name: String) -> URL {
        let encoded = Self.encodedDirectoryName(for: Self.normalizedName(name))
        return playersDirectory.appendingPathComponent(encoded, isDirectory: true)
    }

    func makeSaveService(for name: String) throws -> GameSaveService {
        let directory = playerDirectoryURL(for: name)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return try GameSaveService(fileManager: fileManager, directoryURL: directory)
    }

    // MARK: - Avatars

    func avatarURL(for name: String) -> URL {
        playerDirectoryURL(for: name).appendingPathComponent(Self.avatarFileName)
    }

    func saveAvatar(_ data: Data, for name: String) throws {
        let trimmed = Self.normalizedName(name)
        let roster = try loadRoster()
        guard roster.contains(trimmed) else {
            throw PlayerStateError.playerNotFound
        }

        let directory = playerDirectoryURL(for: trimmed)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = avatarURL(for: trimmed)
        let temporaryURL = url.appendingPathExtension("tmp")
        try data.write(to: temporaryURL, options: .atomic)
        if fileManager.fileExists(atPath: url.path) {
            _ = try fileManager.replaceItemAt(url, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: url)
        }
    }

    func loadAvatar(for name: String) -> Data? {
        let url = avatarURL(for: name)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }

    // MARK: - Orphan cleanup

    /// Removes player directories not listed in the roster, and the legacy root `save.plist`.
    func purgeOrphans() throws {
        let roster = Set(try loadRoster())

        if fileManager.fileExists(atPath: playersDirectory.path),
           let contents = try? fileManager.contentsOfDirectory(
               at: playersDirectory,
               includingPropertiesForKeys: [.isDirectoryKey],
               options: [.skipsHiddenFiles]
           ) {
            for url in contents {
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else {
                    try? fileManager.removeItem(at: url)
                    continue
                }

                guard let name = Self.decodedPlayerName(fromDirectoryName: url.lastPathComponent),
                      roster.contains(name) else {
                    try? fileManager.removeItem(at: url)
                    continue
                }
            }
        }

        let legacySave = rootDirectoryURL.appendingPathComponent(GameSaveService.saveFileName)
        if fileManager.fileExists(atPath: legacySave.path) {
            try? fileManager.removeItem(at: legacySave)
        }
    }

    // MARK: - Name helpers

    nonisolated static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func encodedDirectoryName(for name: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_")
        return name.addingPercentEncoding(withAllowedCharacters: allowed) ?? name
    }

    nonisolated static func decodedPlayerName(fromDirectoryName directoryName: String) -> String? {
        directoryName.removingPercentEncoding
    }

    // MARK: - Private I/O

    private func loadRoster() throws -> [String] {
        guard fileManager.fileExists(atPath: rosterURL.path) else {
            return []
        }
        let data = try Data(contentsOf: rosterURL)
        do {
            return try JSONDecoder().decode([String].self, from: data)
        } catch {
            throw PlayerStateError.corruptData
        }
    }

    private func saveRoster(_ roster: [String]) throws {
        let data = try JSONEncoder().encode(roster)
        let temporaryURL = rosterURL.appendingPathExtension("tmp")
        try data.write(to: temporaryURL, options: .atomic)
        if fileManager.fileExists(atPath: rosterURL.path) {
            _ = try fileManager.replaceItemAt(rosterURL, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: rosterURL)
        }
    }

    private func stateURL(for name: String) -> URL {
        playerDirectoryURL(for: name).appendingPathComponent(Self.stateFileName)
    }

    private func writeState(_ state: PlayerGameState, for name: String) throws {
        let directory = playerDirectoryURL(for: name)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        var stamped = state
        stamped.version = PlayerGameState.currentVersion
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(stamped)

        let url = stateURL(for: name)
        let temporaryURL = url.appendingPathExtension("tmp")
        try data.write(to: temporaryURL, options: .atomic)
        if fileManager.fileExists(atPath: url.path) {
            _ = try fileManager.replaceItemAt(url, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: url)
        }
    }

    private static func decodeState(_ data: Data) throws -> PlayerGameState {
        do {
            let state = try PropertyListDecoder().decode(PlayerGameState.self, from: data)
            guard state.version == PlayerGameState.currentVersion else {
                throw PlayerStateError.unsupportedVersion(state.version)
            }
            return state
        } catch let error as PlayerStateError {
            throw error
        } catch {
            throw PlayerStateError.corruptData
        }
    }
}
