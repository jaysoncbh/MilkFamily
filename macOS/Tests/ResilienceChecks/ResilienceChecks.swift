import Foundation
import NaijiaCore

/// Synthetic records only: these regressions run from a clean source checkout, without private assets or saves.
@main struct ResilienceChecks {
    static func main() {
        do { try run() } catch { print("FAIL: \(error.localizedDescription)"); exit(1) }
    }
    static func run() throws {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("naijia-resilience-" + UUID().uuidString)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch) }
        var characters: [[String: Any]] = [], cards: [[String: Any]] = []
        for (id, grade) in [("A101", 1), ("A102", 1), ("A201", 4)] {
            var frames: [String: Any] = [:]
            for index in 1...4 {
                let action = "B" + id.dropFirst() + "0\(index)", card = "C" + id.dropFirst() + "0\(index)"
                frames["pose\(index)"] = ["id": action, "name": "pose\(index)", "file": "frames/\(action).png", "original": "masters/\(action).png", "cardId": card, "cardStyle": "普通卡"]
                cards.append(["id": card, "characterId": id, "actionId": action, "actionName": "pose\(index)", "name": "Fixture", "rarity": "普通", "style": "普通卡", "file": "cards/\(card).png", "gamePoolOpen": true])
            }
            characters.append(["id": id, "name": "Fixture", "rarityCode": grade, "rarity": "普通", "poseOrder": (1...4).map { "pose\($0)" }, "frames": frames])
        }
        let manifest = scratch.appendingPathComponent("fixture.json")
        try JSONSerialization.data(withJSONObject: ["characters": characters, "cards": cards]).write(to: manifest)
        let library = try AssetLibrary.load(from: manifest)
        let rulesURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("02_配置/正式版规则.json")
        let rules = try PreviewRules.load(from: rulesURL)
        func started() throws -> DemoGame {
            var game = DemoGame(state: .liveInitial(), rules: rules)
            try game.chooseStarter(characterID: "A101", library: library)
            try game.draw(cardID: "C10101", free: true, library: library)
            return game
        }
        func incubating() throws -> DemoGame {
            var game = try started()
            _ = try game.consume(80_000_000, library: library)
            try game.startWaitingEgg(library: library)
            game.state.incubationTokens = 49_000_000
            game.state.incubationBonusTokens = 150
            return game
        }
        var passed = 0
        func check(_ value: @autoclosure () throws -> Bool, _ name: String) throws {
            guard try value() else { throw NSError(domain: "NaijiaResilienceChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: name]) }
            passed += 1; print("PASS \(name)")
        }
        func rejects(_ operation: () throws -> Void) -> Bool {
            do { try operation(); return false } catch { return true }
        }
        var batched = try incubating(), split = batched
        let ledger = batched.state.usageLedger
        _ = try batched.consume(6_000_000, library: library, hatchCharacterID: "A102")
        _ = try split.consume(1_000_000, library: library, hatchCharacterID: "A102")
        _ = try split.consume(5_000_000, library: library, hatchCharacterID: "A102")
        try check(batched.state == split.state && batched.state.cultivationTokens == 5_000_150 && batched.state.usageLedger == ledger, "孵化余量继续培养，分批与整批结果一致且不改真实账本")
        var invalid = try incubating(); let before = invalid.state
        try check(rejects { _ = try invalid.consume(6_000_000, library: library, hatchCharacterID: "missing") } && invalid.state == before, "孵化目标无效时整笔用量、奖励和进度原子回退")
        invalid.state.characterProgress?["A102"] = Int.max
        let overflow = invalid.state
        try check(rejects { _ = try invalid.consume(6_000_000, library: library, hatchCharacterID: "A102") } && invalid.state == overflow, "新伙伴进度溢出时不扣除或部分记录用量")
        var easier = try incubating(); let originalTokens = easier.state.totalTokens
        try easier.setDifficulty(20, library: library)
        try check(easier.state.phase == .cultivating && easier.state.totalTokens == originalTokens && easier.state.hatchCounts?.values.reduce(0, +) == 1, "降低难度跨过门槛时立即孵化且不虚增Token")
        var candy = try incubating(); candy.state.inventory?["milkCandy"] = 1
        let remaining = candy.remainingEggTokens, candyTokens = candy.state.totalTokens
        let candyLedger = candy.state.usageLedger
        try candy.use(.milkCandy, library: library)
        try check(candy.remainingEggTokens == remaining - 150 && candy.state.totalTokens == candyTokens && candy.state.usageLedger == candyLedger, "剩余孵化需求计入奶糖奖励，真实Token仍不变")
        var full = try started(); full.state.freeDraws = 1; full.state.collection["C10101"] = Int.max
        let fullState = full.state
        try check(rejects { try full.draw(cardID: "C10101", free: true, library: library) } && full.state == fullState, "重复卡数量溢出不会崩溃或扣掉抽卡次数")
        let epoch = Date(timeIntervalSince1970: 2_000_000_000)
        var clock = AnimationPlaybackClock(); clock.setPlaying(true, at: epoch)
        try check(clock.elapsed(at: epoch) == 0 && clock.elapsed(at: epoch.addingTimeInterval(0.16)) < 0.17, "新播放从零开始，不使用系统绝对时间")
        clock.setPlaying(false, at: epoch.addingTimeInterval(2))
        clock.setPlaying(true, at: epoch.addingTimeInterval(10_000))
        try check(clock.elapsed(at: epoch.addingTimeInterval(10_001)) == 3, "隐藏动画暂停计时，重新显示不跳过剩余阶段")
        let onceURL = scratch.appendingPathComponent("once.json")
        try JSONSerialization.data(withJSONObject: ["actionId": "B10101", "frameCount": 3, "frameDurationsMs": [100, 200, 100], "loop": false, "frames": [["file": "1.png"], ["file": "2.png"], ["file": "3.png"]]]).write(to: onceURL)
        let once = try AnimationAsset.load(from: onceURL)
        try check(once.frameIndex(elapsed: 0) == 0 && once.frameIndex(elapsed: 0.15) == 1 && once.frameIndex(elapsed: 10) == 2, "一次性动作从首帧推进并在末帧保持")
        let saveURL = scratch.appendingPathComponent("save.json")
        let original = try started().state
        try GameSaveFile.write(original, to: saveURL, library: library)
        let originalBytes = try Data(contentsOf: saveURL)
        _ = try GameSaveFile.read(from: saveURL, library: library)
        try check(try Data(contentsOf: saveURL) == originalBytes, "读取存档不改写原文件")
        var updated = original; updated.coins += 1
        try GameSaveFile.write(updated, to: saveURL, library: library)
        try check(try GameSaveFile.read(from: GameSaveFile.backupURL(for: saveURL), library: library) == original, "成功事务保留上一份有效存档")
        let damaged = Data("broken save".utf8); try damaged.write(to: saveURL)
        try check(rejects { try GameSaveFile.write(updated, to: saveURL, library: library) } && (try Data(contentsOf: saveURL)) == damaged, "损坏存档拒绝覆盖，等待用户选择恢复")
        try GameSaveFile.restoreBackup(for: saveURL, library: library)
        let preserved = try fm.contentsOfDirectory(at: scratch.appendingPathComponent("恢复前存档"), includingPropertiesForKeys: nil)
        try check(try GameSaveFile.read(from: saveURL, library: library) == original && preserved.count == 1 && Data(contentsOf: preserved[0]) == damaged, "明确恢复后取回有效进度，同时保留损坏原件")
        var negative = original; negative.inventory = ["milkCandy": -1]
        try check(rejects { try GameSaveFile.write(negative, to: saveURL, library: library) } && (try GameSaveFile.read(from: saveURL, library: library)) == original, "非法负数状态不会落盘或覆盖好存档")
        try check(rejects { try library.validateRuntimeResources(at: scratch) }, "缺文件素材包在替换当前素材前被拒绝")
        print("\(passed) 项韧性检查全部通过")
    }
}
