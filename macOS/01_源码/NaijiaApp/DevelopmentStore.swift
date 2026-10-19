#if DEBUG
import AppKit
import NaijiaCore

@MainActor
extension AppStore {
    private var developmentBackups: URL {
        primarySaveURL.deletingLastPathComponent().appendingPathComponent("开发测试备份", isDirectory: true)
    }

    func restoreDevelopmentIfNeeded() {
        guard developerToolsAvailable, UserDefaults.standard.bool(forKey: "developmentTesting") else { return }
        do {
            let saved = try readDevelopmentState(developmentSaveURL)
            restoreVisibleState(saved)
            developmentTesting = true
        } catch {
            UserDefaults.standard.set(false, forKey: "developmentTesting")
            notify("测试存档不可用，已恢复正式进度")
        }
    }

    func beginDevelopmentTesting() {
        guard developerToolsAvailable, !developmentTesting, !developerBusy else { return }
        do {
            try writeDevelopmentState(state, to: primarySaveURL)
            try backUpDevelopmentState(state, label: "进入前进度")
            var copy = state
            copy.usageLedger = nil
            try writeDevelopmentState(copy, to: developmentSaveURL)
            usageGeneration += 1
            restoreVisibleState(copy)
            developmentTesting = true
            developmentUndoState = nil
            UserDefaults.standard.set(true, forKey: "developmentTesting")
            selectedCard = nil
            onPreferencesChanged?()
            notify("已进入测试")
        } catch { notify(error.localizedDescription) }
    }

    func endDevelopmentTesting() async {
        guard developerToolsAvailable, developmentTesting, !developerBusy else { return }
        developerBusy = true
        usageGeneration += 1
        defer { developerBusy = false }
        do {
            var original = try readDevelopmentState(primarySaveURL)
            let snapshot = try await usageScanner.scan(roots: usageRoots)
            // Keep original progress while advancing the real log baseline past the test interval.
            var ledger = original.usageLedger ?? UsageLedger()
            ledger.initialized = false
            _ = ledger.apply(snapshot.entries)
            original.usageLedger = ledger
            showUsageSnapshot(snapshot)
            try writeDevelopmentState(original, to: primarySaveURL)
            restoreVisibleState(original)
            developmentTesting = false
            developmentUndoState = nil
            UserDefaults.standard.set(false, forKey: "developmentTesting")
            selectedCard = nil
            onPreferencesChanged?()
            notify("已恢复正式进度")
        } catch { notify(error.localizedDescription) }
    }

    func developerSetTokens(_ tokens: Int) {
        mutateDevelopment("设定Token") { next in
            next = try DevelopmentSimulation.replaying(tokens, from: next, library: library)
        }
    }

    func developerAddTokens(_ tokens: Int, hatchCharacterID: String? = nil) {
        mutateDevelopment("增加Token") { next in
            let hatch = hatchCharacterID ?? next.hatchCharacterID(library: library)
            next = try DevelopmentSimulation.adding(tokens, to: next, library: library, hatchCharacterID: hatch)
        }
    }

    func developerFinishStage(hatchCharacterID: String? = nil) {
        do {
            let tokens = try DevelopmentSimulation.tokensToFinishStage(game, library: library)
            developerAddTokens(tokens, hatchCharacterID: hatchCharacterID)
        } catch { notify(error.localizedDescription) }
    }

    func developerPrepareIncubation() {
        mutateDevelopment("准备孵化") { next in
            next = try DevelopmentSimulation.preparingIncubation(next, library: library)
        }
    }

    func developerResetEverything() {
        mutateDevelopment("重置所有测试进度") { next in
            next = DevelopmentSimulation.resetting(rules: next.rules)
        }
    }

    func developerUndo() {
        guard let previous = developmentUndoState else { return }
        mutateDevelopment("撤销修改") { $0.state = previous }
    }

    func showDevelopmentBackups() { NSWorkspace.shared.open(developmentBackups) }

    private func mutateDevelopment(_ label: String, _ mutation: (inout DemoGame) throws -> Void) {
        guard developerToolsAvailable, developmentTesting, !developerBusy else { return }
        do {
            let previous = state
            var next = game
            try mutation(&next)
            try backUpDevelopmentState(previous, label: label)
            guard update({ $0 = next }) else { return }
            developmentUndoState = previous
            selectedCard = nil
            notify("\(compact(state.totalTokens)) Token")
        } catch { notify(error.localizedDescription) }
    }

    private func readDevelopmentState(_ url: URL) throws -> DemoState {
        try GameSaveFile.read(from: url, library: library)
    }

    private func writeDevelopmentState(_ saved: DemoState, to url: URL) throws {
        try GameSaveFile.write(saved, to: url, library: library)
    }

    private func backUpDevelopmentState(_ saved: DemoState, label: String) throws {
        let name = "\(Int(Date().timeIntervalSince1970))-\(label)-\(UUID().uuidString.prefix(8)).json"
        try writeDevelopmentState(saved, to: developmentBackups.appendingPathComponent(name))
    }
}
#endif
