import Foundation

enum GameSaveError: Error, Equatable {
    case invalidEntityLetter
    case unsupportedVersion(Int)
    case corruptData
}

actor GameSaveService {
    static let saveFileName = "save.plist"

    private let fileManager: FileManager
    private let saveURL: URL
    private var saveGeneration: UInt64 = 0

    init(fileManager: FileManager = .default, directoryURL: URL? = nil) throws {
        self.fileManager = fileManager

        if let directoryURL {
            self.saveURL = directoryURL.appendingPathComponent(Self.saveFileName)
        } else {
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = appSupport.appendingPathComponent("PadawanAdventures", isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            self.saveURL = directory.appendingPathComponent(Self.saveFileName)
        }
    }

    func save(_ world: GameWorld) async throws {
        saveGeneration += 1
        let generation = saveGeneration
        let snapshot = world

        let data = try await Task.detached(priority: .utility) {
            try Self.encode(GameSaveFile(world: snapshot))
        }.value

        guard generation == saveGeneration else { return }

        try writeAtomically(data)
    }

    func load() async throws -> GameWorld? {
        guard fileManager.fileExists(atPath: saveURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: saveURL)
        return try Self.decode(data).world
    }

    func delete() async throws {
        saveGeneration += 1
        guard fileManager.fileExists(atPath: saveURL.path) else { return }
        try fileManager.removeItem(at: saveURL)
    }

    var saveFileURL: URL {
        saveURL
    }

    private func writeAtomically(_ data: Data) throws {
        let temporaryURL = saveURL.appendingPathExtension("tmp")
        try data.write(to: temporaryURL, options: .atomic)

        if fileManager.fileExists(atPath: saveURL.path) {
            _ = try fileManager.replaceItemAt(saveURL, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: saveURL)
        }
    }

    private static func encode(_ file: GameSaveFile) throws -> Data {
        var stamped = file
        stamped.version = GameSaveFile.currentVersion
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(stamped)
    }

    private static func decode(_ data: Data) throws -> GameSaveFile {
        let decoder = PropertyListDecoder()
        do {
            let file = try decoder.decode(GameSaveFile.self, from: data)
            guard file.version == GameSaveFile.currentVersion else {
                throw GameSaveError.unsupportedVersion(file.version)
            }
            return file
        } catch let error as GameSaveError {
            throw error
        } catch {
            throw GameSaveError.corruptData
        }
    }
}
