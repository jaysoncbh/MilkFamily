import Foundation
import NaijiaCore

@main
struct UsageChecks {
    static func require(_ value: Bool, _ name: String) {
        guard value else { print("FAIL \(name)"); exit(1) }
        print("PASS \(name)")
    }
    static func main() async throws {
        if CommandLine.arguments.contains("--local") {
            let cache = URL(fileURLWithPath: "/tmp/naijia-real-usage-check-cache.json")
            let reader = LocalUsageScanner(cacheURL: cache)
            let started = Date()
            let snapshot = try await reader.scan(roots: LocalUsageScanner.defaultRoots())
            let formatter = ISO8601DateFormatter()
            let report: [String: Any] = ["checkedAt": formatter.string(from: snapshot.fetchedAt), "elapsedSeconds": Date().timeIntervalSince(started), "distinctUsageEntries": snapshot.entries.count,
                "providers": snapshot.providers.map { ["provider": $0.provider.rawValue, "files": $0.files, "todayTokens": $0.today, "allLocalTokens": $0.allTime, "error": $0.error as Any] as [String: Any] }]
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            print(String(decoding: data, as: UTF8.self))
            try data.write(to: URL(fileURLWithPath: "/tmp/naijia-real-usage-check.json"))
            return
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("naijia-usage-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let codex = root.appendingPathComponent("codex")
        let claude = root.appendingPathComponent("claude")
        for folder in [codex, claude] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        func write(_ name: String, _ lines: [[String: Any]], folder: URL, append: Bool = false) throws {
            let data = try lines.reduce(into: Data()) { result, object in result.append(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])); result.append(10) }
            let url = folder.appendingPathComponent(name)
            if append { let handle = try FileHandle(forWritingTo: url); try handle.seekToEnd(); try handle.write(contentsOf: data); try handle.close() }
            else { try data.write(to: url) }
        }
        func meta(_ id: String, parent: String? = nil) -> [String: Any] {
            var payload: [String: Any] = ["id": id]
            if let parent { payload["forked_from_id"] = parent }
            return ["type": "session_meta", "timestamp": "2026-10-07T01:00:20.000Z", "payload": payload]
        }
        func token(_ total: Int, timestamp: String, cached: Int = 60) -> [String: Any] {
            return ["type": "event_msg", "timestamp": timestamp, "payload": ["type": "token_count", "info": ["last_token_usage": ["input_tokens": 100,"cached_input_tokens": cached,"output_tokens": 20,"reasoning_output_tokens": 15,"total_tokens": 120], "total_token_usage": ["input_tokens": total - 20,"cached_input_tokens": cached,"output_tokens": 20,"total_tokens": total]]]]
        }
        let t1 = "2026-10-07T01:00:00.000Z", t2 = "2026-10-07T01:00:10.000Z"
        try write("parent.jsonl", [meta("parent"),token(120,timestamp:t1),token(120,timestamp:t1),token(240,timestamp:t2)], folder: codex)
        try write("fork.jsonl", [meta("child",parent:"parent"),token(120,timestamp:t1),token(240,timestamp:t2),token(360,timestamp:"2026-10-07T01:00:30.000Z")], folder: codex)
        func claudeMessage(_ id: String, output: Int, timestamp: String) -> [String: Any] {
            ["type":"assistant","timestamp":timestamp,"message":["id":id,"usage":["input_tokens":10,"cache_read_input_tokens":100,"cache_creation_input_tokens":20,"output_tokens":output]]]
        }
        try write("a.jsonl", [claudeMessage("message",output:5,timestamp:t1),claudeMessage("message",output:15,timestamp:t2)], folder: claude)
        try write("b.jsonl", [claudeMessage("message",output:15,timestamp:t2)], folder: claude)
        let roots: [UsageProvider:[URL]] = [.codex:[codex,codex],.claude:[claude]]
        let cache = root.appendingPathComponent("cache.json")
        let reader = LocalUsageScanner(cacheURL: cache)
        let first = try await reader.scan(roots:roots)
        require(first.providers.first { $0.provider == .codex }?.allTime == 360,"Codex 重复快照、分支复制、缓存与推理不重复累加")
        require(first.providers.first { $0.provider == .claude }?.allTime == 145,"Claude 流式及跨文件去重并包含两类缓存")
        let second = try await reader.scan(roots:roots)
        require(second.entries.sorted { $0.id < $1.id } == first.entries.sorted { $0.id < $1.id },"重复扫描幂等")
        let restored = LocalUsageScanner(cacheURL: cache)
        let third = try await restored.scan(roots:roots)
        require(third.entries.count == first.entries.count,"读取缓存后记录稳定")
        try write("parent.jsonl",[token(360,timestamp:"2026-10-07T01:00:40.000Z")],folder:codex,append:true)
        let appended = try await reader.scan(roots: roots)
        require(appended.providers.first { $0.provider == .codex }?.allTime == 480,"只追加新用量，父子独立新调用均计数")
        let partial = codex.appendingPathComponent("partial.jsonl")
        let line = try JSONSerialization.data(withJSONObject: token(120,timestamp:t2))
        try (try JSONSerialization.data(withJSONObject: meta("partial")) + Data([10]) + line).write(to: partial)
        let unfinished = try await reader.scan(roots: roots)
        require(unfinished.providers.first { $0.provider == .codex }?.allTime == 480,"未完成日志行不计入")
        let handle = try FileHandle(forWritingTo: partial); try handle.seekToEnd(); try handle.write(contentsOf: Data([10])); try handle.close()
        let complete = try await reader.scan(roots: roots)
        require(complete.providers.first { $0.provider == .codex }?.allTime == 600,"补齐日志行后只计一次")
        try write("partial.jsonl",[meta("partial"),token(120,timestamp:t2)],folder:codex)
        let truncated = try await reader.scan(roots:roots)
        require(truncated.providers.first { $0.provider == .codex }?.allTime == 600,"重写相同日志不重复")
        var ledger = UsageLedger(startedAt: .distantPast)
        require(ledger.apply(first.entries) == 0,"首次历史导入不奖励")
        require(ledger.apply(appended.entries) == 120,"只奖励接入后的新调用")
        require(ledger.apply(appended.entries) == 0,"相同快照不重复奖励")
        let saved = try JSONDecoder().decode(UsageLedger.self, from: JSONEncoder().encode(ledger))
        var relaunched = saved
        require(relaunched.apply(appended.entries) == 0,"重启后不重复奖励")
        var streaming = first.entries
        if let i = streaming.firstIndex(where: { $0.provider == .claude }) { streaming[i].output += 10 }
        var streamLedger = UsageLedger(); _ = streamLedger.apply(first.entries)
        require(streamLedger.apply(streaming) == 10,"已知历史消息追加输出只奖励新增部分")
        var afterTesting = saved
        afterTesting.initialized = false
        require(afterTesting.apply(streaming) == 0 && afterTesting.apply(streaming) == 0,"退出开发测试时重建基线，不重放测试期间用量")
        print("14 项真实用量读取检查全部通过")
    }
}
