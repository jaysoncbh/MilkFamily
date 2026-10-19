import Foundation

public enum SaveFileError: LocalizedError {
    case invalidState, unreadable
    public var errorDescription: String? {
        switch self {
        case .invalidState: "存档中的进度或设置无效，原文件已保留"
        case .unreadable: "存档无法读取，原文件已保留"
        }
    }
}

public enum GameSaveFile {
    public static func backupURL(for url: URL) -> URL {
        url.deletingPathExtension().appendingPathExtension("上次有效.json")
    }

    public static func validate(_ state: DemoState, library: AssetLibrary) throws {
        guard state.schemaVersion == 1,
              library.character(state.activeCharacterId) != nil,
              library.character(state.desktopCharacterId) != nil,
              (1...4).contains(state.eggGrade),
              state.totalTokens >= 0, state.cultivationTokens >= 0,
              state.coins >= 0, state.freeDraws >= 0,
              state.incubationTokens.isFinite, state.incubationTokens >= 0,
              (state.incubationBonusTokens ?? 0).isFinite, (state.incubationBonusTokens ?? 0) >= 0,
              state.petSize.isFinite, (80...180).contains(state.petSize),
              state.collection.values.allSatisfy({ $0 >= 0 }),
              (state.inventory ?? [:]).values.allSatisfy({ $0 >= 0 }),
              (state.characterProgress ?? [:]).values.allSatisfy({ $0 >= 0 }),
              (state.hatchCounts ?? [:]).values.allSatisfy({ $0 >= 0 }),
              (state.usageLedger?.credited ?? [:]).values.allSatisfy({ $0 >= 0 }) else {
            throw SaveFileError.invalidState
        }
    }

    public static func read(from url: URL, library: AssetLibrary) throws -> DemoState {
        do {
            let state = try JSONDecoder().decode(DemoState.self, from: Data(contentsOf: url))
            try validate(state, library: library)
            return state
        } catch { throw SaveFileError.unreadable }
    }

    /// Retain one known-good previous transaction. A broken existing save is never overwritten.
    public static func write(_ state: DemoState, to url: URL, library: AssetLibrary) throws {
        try validate(state, library: library)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: url.path) {
            let previous = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(DemoState.self, from: previous)
            try validate(decoded, library: library)
            if previous == data { return }
            try previous.write(to: backupURL(for: url), options: .atomic)
        }
        try data.write(to: url, options: .atomic)
    }

    /// Called only after the user chooses recovery. Preserve the damaged file separately.
    public static func restoreBackup(for url: URL, library: AssetLibrary) throws {
        let backup = backupURL(for: url)
        _ = try read(from: backup, library: library)
        let data = try Data(contentsOf: backup)
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            let folder = url.deletingLastPathComponent().appendingPathComponent("恢复前存档", isDirectory: true)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let preserved = folder.appendingPathComponent(UUID().uuidString + "_" + url.lastPathComponent)
            try fm.copyItem(at: url, to: preserved)
        }
        try data.write(to: url, options: .atomic)
    }
}
