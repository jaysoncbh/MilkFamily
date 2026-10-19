import Foundation

public struct DailyUsage: Identifiable, Sendable {
    public let date: Date
    public let day: Int
    public let tokens: Int
    public let isToday: Bool
    public let isFuture: Bool
    public var id: Date { date }
}

/// Read-only statistics from deduplicated log events. Never used to award game progress.
public struct UsageHistory: Sendable {
    public let today: Int
    public let week: Int
    public let month: Int
    public let total: Int
    public let monthStart: Date
    public let days: [DailyUsage]
    public var peak: Int { days.map(\.tokens).max() ?? 0 }

    public init(entries: [UsageEntry], now: Date, calendar sourceCalendar: Calendar = .current) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = sourceCalendar.timeZone
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        let startToday = calendar.startOfDay(for: now)
        let startWeek = calendar.dateInterval(of: .weekOfYear, for: now)!.start
        let startMonth = calendar.dateInterval(of: .month, for: now)!.start
        let count = calendar.range(of: .day, in: .month, for: now)!.count
        var totals = [Int](repeating: 0, count: count)
        var today = 0, week = 0, month = 0, total = 0
        // Normally the scanner already resolves IDs. Retain the largest streamed snapshot if repeated.
        var unique: [String: UsageEntry] = [:]
        for entry in entries where entry.date <= now && entry.input >= 0 && entry.output >= 0 && entry.cacheRead >= 0 && entry.cacheWrite >= 0 {
            if let old = unique[entry.id], old.total >= entry.total { continue }
            unique[entry.id] = entry
        }
        func add(_ value: Int, to amount: inout Int) throws {
            let sum = amount.addingReportingOverflow(value)
            guard !sum.overflow else { throw GameError.tokenOverflow }
            amount = sum.partialValue
        }
        for entry in unique.values {
            try add(entry.total, to: &total)
            if entry.date >= startToday { try add(entry.total, to: &today) }
            if entry.date >= startWeek { try add(entry.total, to: &week) }
            if entry.date >= startMonth {
                try add(entry.total, to: &month)
                let index = calendar.component(.day, from: entry.date) - 1
                try add(entry.total, to: &totals[index])
            }
        }
        self.today = today; self.week = week; self.month = month; self.total = total
        monthStart = startMonth
        days = totals.enumerated().map { index, tokens in
            let date = calendar.date(byAdding: .day, value: index, to: startMonth)!
            return DailyUsage(date: date, day: index + 1, tokens: tokens, isToday: date == startToday, isFuture: date > startToday)
        }
    }
}
