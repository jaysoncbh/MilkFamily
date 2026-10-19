import Foundation
import NaijiaCore

@main struct UsageHistoryChecks {
    static func main() {
        do { try run() } catch { print("FAIL \(error)"); exit(1) }
    }
    static func run() throws {
        func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
        func entry(_ id: String, _ timestamp: String, _ input: Int, cache: Int = 0) throws -> UsageEntry {
            let data = try JSONSerialization.data(withJSONObject: ["id": id, "provider": "codex", "date": date(timestamp).timeIntervalSinceReferenceDate, "input": input, "output": 0, "cacheRead": cache, "cacheWrite": 0])
            return try JSONDecoder().decode(UsageEntry.self, from: data)
        }
        var passed = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) throws {
            guard condition() else { throw NSError(domain: "UsageHistoryChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: name]) }
            passed += 1; print("PASS \(name)")
        }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = date("2026-10-19T04:00:00Z")
        let entries = try [entry("old", "2026-09-30T15:59:00Z", 10), entry("monday", "2026-10-12T00:00:00Z", 30), entry("sunday", "2026-10-18T15:59:59Z", 40), entry("midnight", "2026-10-18T16:00:00Z", 50), entry("now", "2026-10-19T04:00:00Z", 60), entry("future", "2026-10-19T04:00:01Z", 70), entry("stream", "2026-10-19T00:00:00Z", 80), entry("stream", "2026-10-19T00:00:00Z", 160)]
        let history = try UsageHistory(entries: entries, now: now, calendar: calendar)
        try check(history.total == 350 && history.month == 340, "累计包含历史，月统计从本地月初开始")
        try check(history.week == 270 && history.today == 270, "周一重置自然周，本地午夜重置当天")
        try check(history.days[17].tokens == 40 && history.days[18].tokens == 270, "UTC日志按本地日期分桶，最大流式快照只算一次")
        try check(history.days.count == 31 && history.days.filter(\.isFuture).count == 12 && history.days.filter(\.isToday).count == 1, "自然月完整天数、今日与未来天区分")
        try check(history.peak == 270 && history.days.dropFirst(19).allSatisfy { $0.tokens == 0 }, "峰值来自实际日期，未来事件不进入任何统计")
        let cross = try UsageHistory(entries: [entry("a", "2026-03-30T01:00:00Z", 100), entry("b", "2026-03-31T01:00:00Z", 200), entry("c", "2026-04-01T01:00:00Z", 300)], now: date("2026-04-01T04:00:00Z"), calendar: calendar)
        try check(cross.week == 600 && cross.month == 300 && cross.days.count == 30, "跨月的本周保留前一月用量，30天月份正确")
        let leap = try UsageHistory(entries: [], now: date("2024-02-29T04:00:00Z"), calendar: calendar)
        let february = try UsageHistory(entries: [], now: date("2026-02-28T04:00:00Z"), calendar: calendar)
        try check(leap.days.count == 29 && february.days.count == 28 && leap.total == 0 && leap.peak == 0, "闰月、平年与空日志不补造柱形数据")
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let daylight = try UsageHistory(entries: [entry("sun", "2026-03-09T06:59:59Z", 50), entry("mon", "2026-03-09T07:00:00Z", 60)], now: date("2026-03-09T07:30:00Z"), calendar: calendar)
        try check(daylight.week == 60 && daylight.today == 60 && daylight.month == 110 && daylight.days[7].tokens == 50, "夏令时23小时日按日历处理，不假设每日86400秒")
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let cache = try UsageHistory(entries: [entry("cache", "2026-10-19T00:00:00Z", 100, cache: 900)], now: now, calendar: calendar)
        try check(cache.total == 1000 && cache.today == 1000, "缓存Token只计入真实总量一次")
        let snapshot = try UsageSnapshot(entries: entries, providers: [], fetchedAt: now, calendar: calendar)
        try check(snapshot.today == history.today && snapshot.entries.count == entries.count && snapshot.history.total == history.total, "快照聚合不更改日志条目和真实账本输入")
        var ledger = UsageLedger(startedAt: .distantPast)
        let initial = ledger.apply(entries)
        let before = ledger
        _ = try UsageHistory(entries: entries, now: now, calendar: calendar)
        try check(initial == 0 && ledger == before && ledger.apply(entries) == 0, "历史统计不触发成长奖励，也不改变去重账本")
        do {
            _ = try UsageHistory(entries: [entry("max1", "2026-10-19T00:00:00Z", Int.max), entry("max2", "2026-10-19T00:00:00Z", 1)], now: now, calendar: calendar)
            throw NSError(domain: "UsageHistoryChecks", code: 2)
        } catch GameError.tokenOverflow { passed += 1; print("PASS 数字溢出明确报错，不回绕或虚构截断总量") }
        print("\(passed) 项用量历史检查全部通过")
    }
}
