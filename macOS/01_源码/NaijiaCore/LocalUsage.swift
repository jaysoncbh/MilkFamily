import Foundation
import CryptoKit
import CoreFoundation

public enum UsageProvider: String, Codable, CaseIterable, Sendable { case codex, claude }

public struct UsageEntry: Codable, Sendable, Equatable {
    public var id: String
    public var provider: UsageProvider
    public var date: Date
    public var input: Int
    public var output: Int
    public var cacheRead: Int
    public var cacheWrite: Int
    public var total: Int { input + output + cacheRead + cacheWrite }
}

public struct ProviderUsage: Sendable {
    public var provider: UsageProvider
    public var files: Int = 0
    public var today: Int = 0
    public var allTime: Int = 0
    public var lastEvent: Date?
    public var error: String?
}

public struct UsageSnapshot: Sendable {
    public let entries: [UsageEntry]
    public let providers: [ProviderUsage]
    public let fetchedAt: Date
    public let history: UsageHistory
    public var today: Int { history.today }
    public init(entries: [UsageEntry], providers: [ProviderUsage], fetchedAt: Date, calendar: Calendar = .current) throws {
        self.entries = entries; self.providers = providers; self.fetchedAt = fetchedAt
        history = try UsageHistory(entries: entries, now: fetchedAt, calendar: calendar)
    }
}

// The ledger and game state are saved together. Historical imports never grant growth.
public struct UsageLedger: Codable, Sendable, Equatable {
    public var startedAt: Date
    public var initialized: Bool
    public var credited: [String: Int]
    public init(startedAt: Date = Date()) {
        self.startedAt = startedAt; initialized = false; credited = [:]
    }
    public mutating func apply(_ entries: [UsageEntry]) -> Int {
        var delta = 0
        for entry in entries {
            let previous = credited[entry.id, default: 0]
            if initialized, previous > 0 || entry.date >= startedAt { delta += max(0, entry.total - previous) }
            credited[entry.id] = max(previous, entry.total)
        }
        initialized = true
        return delta
    }
}

private struct TokenVector: Codable, Equatable, Sendable {
    var input: Int; var cached: Int; var output: Int; var reasoning: Int; var total: Int
    init(_ raw: [String: Any]) {
        input = safeToken(raw["input_tokens"]); cached = safeToken(raw["cached_input_tokens"])
        output = safeToken(raw["output_tokens"]); reasoning = safeToken(raw["reasoning_output_tokens"])
        total = safeToken(raw["total_tokens"])
    }
    var signature: String { "\(input),\(cached),\(output),\(reasoning),\(total)" }
}

private struct CodexEvent: Codable, Sendable {
    var entry: UsageEntry
    var session: String
    var cumulative: TokenVector?
    var last: TokenVector
    var signature: String? { cumulative.map { $0.signature + "|" + last.signature } }
}

private struct UsageFile: Codable, Sendable {
    var provider: UsageProvider
    var offset: UInt64 = 0
    var size: UInt64 = 0
    var modified: Date = .distantPast
    var session: String?
    var currentSession: String?
    var parent: String?
    var createdAt: Date?
    var subagent = false
    var codex: [CodexEvent] = []
    var claude: [String: UsageEntry] = [:]

    mutating func accept(_ data: Data, fallbackID: String) {
        let marker = provider == .codex ? Data("token_count".utf8) : Data("\"usage\"".utf8)
        let isMeta = provider == .codex && data.range(of: Data("\"session_meta\"".utf8)) != nil
        guard isMeta || data.range(of: marker) != nil,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if isMeta, object["type"] as? String == "session_meta", let meta = object["payload"] as? [String: Any] {
            let id = meta["id"] as? String ?? meta["session_id"] as? String
            if session == nil {
                session = id; parent = meta["forked_from_id"] as? String
                createdAt = ((meta["timestamp"] ?? object["timestamp"]) as? String).flatMap(usageDate)
                if let source = meta["source"] as? [String: Any] { subagent = source["subagent"] != nil }
            }
            currentSession = id
            return
        }
        guard let timestamp = object["timestamp"] as? String, let date = usageDate(timestamp) else { return }
        if provider == .codex {
            guard object["type"] as? String == "event_msg",
                  let payload = object["payload"] as? [String: Any], payload["type"] as? String == "token_count",
                  let info = payload["info"] as? [String: Any], let raw = info["last_token_usage"] as? [String: Any] else { return }
            let last = TokenVector(raw)
            let cumulative = (info["total_token_usage"] as? [String: Any]).map(TokenVector.init)
            let owner = currentSession ?? session ?? fallbackID
            let cached = min(last.input, last.cached)
            var input = last.input - cached
            if last.input + last.output == 0, last.total > 0 {
                let previous = codex.last?.cumulative?.total ?? 0
                if cumulative == nil || cumulative?.total == last.total || (cumulative?.total ?? 0) > previous {
                    input = last.total
                }
            }
            let entry = UsageEntry(id: "", provider: .codex, date: date, input: input, output: last.output, cacheRead: cached, cacheWrite: 0)
            let event = CodexEvent(entry: entry, session: owner, cumulative: cumulative, last: last)
            if let signature = event.signature, let previous = codex.last,
               previous.session == owner, previous.signature == signature { return }
            codex.append(event)
        } else {
            guard object["type"] as? String == "assistant", let message = object["message"] as? [String: Any],
                  let raw = message["usage"] as? [String: Any] else { return }
            let messageID = message["id"] as? String ?? object["uuid"] as? String ?? digest(data)
            // A message can be streamed into several content blocks with the same usage.
            let id = "claude|\(messageID)|\(object["requestId"] as? String ?? "")"
            let entry = UsageEntry(id: id, provider: .claude, date: date,
                                   input: safeToken(raw["input_tokens"]), output: safeToken(raw["output_tokens"]),
                                   cacheRead: safeToken(raw["cache_read_input_tokens"]), cacheWrite: safeToken(raw["cache_creation_input_tokens"]))
            if entry.total >= claude[id, default: entry].total { claude[id] = entry }
        }
    }
}

// Independently implemented from the local-log approach documented by PokeTokenBar (MIT).
// Cache only token metadata; never store prompts, response text, credentials or source lines.
public actor LocalUsageScanner {
    private var files: [String: UsageFile] = [:]
    private let cacheURL: URL?
    public init(cacheURL: URL? = nil) {
        self.cacheURL = cacheURL
        if let cacheURL, let data = try? Data(contentsOf: cacheURL),
           let decoded = try? JSONDecoder().decode([String: UsageFile].self, from: data) { files = decoded }
    }

    public static func defaultRoots() -> [UsageProvider: [URL]] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let env = ProcessInfo.processInfo.environment
        let codex = env["CODEX_HOME"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".codex")
        var claude = [home.appendingPathComponent(".claude/projects"), home.appendingPathComponent(".config/claude/projects")]
        if let custom = env["CLAUDE_CONFIG_DIR"] { claude.append(URL(fileURLWithPath: custom).appendingPathComponent("projects")) }
        return [.codex: [codex.appendingPathComponent("sessions"), codex.appendingPathComponent("archived_sessions")], .claude: claude]
    }

    public func scan(roots: [UsageProvider: [URL]], now: Date = Date()) throws -> UsageSnapshot {
        var status: [UsageProvider: ProviderUsage] = [:]
        var visited = Set<String>()
        var changed = false
        for provider in UsageProvider.allCases {
            var providerStatus = ProviderUsage(provider: provider)
            for root in roots[provider, default: []] where FileManager.default.fileExists(atPath: root.path) {
                let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
                let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles], errorHandler: { _, _ in
                    providerStatus.error = "部分用量目录暂时无法读取"
                    return true
                })
                guard let iterator else { providerStatus.error = "用量目录暂时无法读取"; continue }
                for case let url as URL in iterator where url.pathExtension == "jsonl" {
                    let canonical = url.resolvingSymlinksInPath().path
                    guard visited.insert(canonical).inserted else { continue }
                    providerStatus.files += 1
                    do {
                        let values = try url.resourceValues(forKeys: Set(keys))
                        guard values.isRegularFile == true else { continue }
                        let size = UInt64(max(0, values.fileSize ?? 0))
                        let modified = values.contentModificationDate ?? .distantPast
                        var record = files[canonical] ?? UsageFile(provider: provider)
                        if record.size == size && record.modified == modified { continue }
                        if size < record.size || (size == record.size && record.modified != modified) { record = UsageFile(provider: provider) }
                        try readNewLines(url, into: &record)
                        record.size = size; record.modified = modified
                        files[canonical] = record; changed = true
                    } catch { providerStatus.error = "部分用量日志暂时无法读取" }
                }
            }
            status[provider] = providerStatus
        }
        // Retain previously read files through archive moves/deletion; canonical IDs deduplicate them.
        let entries = Self.resolve(Array(files.values))
        let start = Calendar.current.startOfDay(for: now)
        for entry in entries {
            status[entry.provider]?.allTime += entry.total
            if entry.date >= start, entry.date <= now { status[entry.provider]?.today += entry.total }
            if entry.date > (status[entry.provider]?.lastEvent ?? .distantPast) { status[entry.provider]?.lastEvent = entry.date }
        }
        if changed, let cacheURL {
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(files).write(to: cacheURL, options: .atomic)
        }
        return try UsageSnapshot(entries: entries, providers: UsageProvider.allCases.compactMap { status[$0] }, fetchedAt: now)
    }

    private func readNewLines(_ url: URL, into record: inout UsageFile) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: record.offset)
        var buffer = Data()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            buffer.append(chunk)
            var start = buffer.startIndex
            while let end = buffer[start...].firstIndex(of: 10) {
                let line = Data(buffer[start..<end])
                autoreleasepool { record.accept(line, fallbackID: url.lastPathComponent) }
                record.offset += UInt64(end - start + 1)
                start = end + 1
            }
            if start > buffer.startIndex { buffer = Data(buffer[start...]) }
        }
        // An incomplete final JSONL line is read again on the next poll.
    }

    private static func resolve(_ records: [UsageFile]) -> [UsageEntry] {
        let grouped = Dictionary(grouping: records.filter { $0.provider == .codex }, by: { $0.session ?? UUID().uuidString })
        let codex = grouped.values.compactMap { $0.max(by: { $0.codex.count < $1.codex.count }) }
        let bySession = Dictionary(grouping: codex.filter { $0.session != nil }, by: { $0.session! })
        var memo: [String: [CodexEvent]] = [:]
        func history(_ record: UsageFile, visiting: Set<String> = []) -> [CodexEvent] {
            let id = record.session ?? ""
            if let cached = memo[id] { return cached }
            guard !visiting.contains(id) else { return record.codex }
            var inherited = [CodexEvent]()
            if let parent = record.parent {
                for candidate in bySession[parent, default: []] {
                    let parentEvents = history(candidate, visiting: visiting.union([id]))
                    var count = 0
                    while count < record.codex.count, count < parentEvents.count,
                          parentEvents[count].entry.date <= (record.createdAt ?? .distantFuture),
                          let signature = record.codex[count].signature, signature == parentEvents[count].signature { count += 1 }
                    if count > inherited.count { inherited = Array(parentEvents.prefix(count)) }
                }
            }
            var result = inherited
            var epoch = 0
            var previousTotal: Int?
            for var event in record.codex.dropFirst(inherited.count) {
                let owner = record.parent == nil ? event.session : id
                if let total = event.cumulative?.total {
                    if let previousTotal, total < previousTotal { epoch += 1 }
                    previousTotal = total
                }
                let signature = event.signature ?? "\(event.entry.date.timeIntervalSince1970)|\(event.last.signature)"
                event.entry.id = "codex|\(owner)|\(epoch)|\(signature)"
                result.append(event)
            }
            if !id.isEmpty { memo[id] = result }
            return result
        }
        var result: [String: UsageEntry] = [:]
        for record in codex {
            for event in history(record) {
                if result[event.entry.id] == nil || event.entry.date < result[event.entry.id]!.date { result[event.entry.id] = event.entry }
            }
        }
        for record in records where record.provider == .claude {
            for (id, entry) in record.claude where entry.total >= (result[id]?.total ?? 0) { result[id] = entry }
        }
        return Array(result.values)
    }
}

private func safeToken(_ value: Any?) -> Int {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return 0 }
    let count = number.doubleValue
    return count.isFinite && count >= 0 && count < 1e15 ? Int(count) : 0
}

private func usageDate(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
}

private func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
