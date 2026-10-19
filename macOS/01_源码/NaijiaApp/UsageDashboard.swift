import SwiftUI
import NaijiaCore

struct UsageStrip: View {
    @ObservedObject var store: AppStore
    private var history: UsageHistory? { store.usageSnapshot?.history }
    private var tokens: Int? { store.developmentTesting ? store.state.totalTokens : history?.today }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                Text(L(store.developmentTesting ? "测试 Token" : "今日 Token"))
                    .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.66))
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(tokens.map(compact) ?? "—").font(.system(size: 28, weight: .bold)).monospacedDigit()
                    if let tokens, tokens >= 1_000 {
                        Text(tokens.formatted(.number.grouping(.automatic)))
                            .font(.system(size: 10)).monospacedDigit().foregroundStyle(Color.primary.opacity(0.66))
                    }
                    Spacer(minLength: 0)
                }.lineLimit(1).minimumScaleFactor(0.8)
            }
            HStack(alignment: .top, spacing: 12) {
                metric("本周", value: history?.week)
                metric("本月", value: history?.month)
                metric("累计 Token", value: history?.total)
            }
            .help(L("周一开始的自然周；自然月；本机可读取的全部去重历史用量。统计与游戏成长分开。"))
            if let history {
                UsageMonthChart(history: history, language: store.state.language ?? "zh-Hans")
            } else {
                Text(L(store.usageReading ? "正在读取每日用量…" : "连接本机日志后显示每日用量"))
                    .font(.system(size: 10)).foregroundStyle(Color.primary.opacity(0.66))
                    .frame(maxWidth: .infinity, minHeight: 88)
            }
            if store.developmentTesting {
                Text(L("周、月和累计统计仍为真实日志用量"))
                    .font(.system(size: 9)).foregroundStyle(Color.primary.opacity(0.66))
            } else {
                HStack(spacing: 25) {
                    ForEach(store.usageSnapshot?.providers ?? [], id: \.provider) { usage in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(usage.provider == .codex ? "Codex" : "Claude Code")
                                .font(.system(size: 10)).foregroundStyle(Color.primary.opacity(0.66))
                            Text(compact(usage.today)).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                        }.help(L(usage.error ?? (usage.files > 0 ? "已连接本机日志" : "未发现本机日志")))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func metric(_ title: String, value: Int?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L(title)).font(.system(size: 10)).foregroundStyle(Color.primary.opacity(0.66))
            Text(value.map(compact) ?? "—").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.75)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .help(value.map { $0.formatted() + " Token" } ?? L("正在读取每日用量…"))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L(title))
            .accessibilityValue(value.map { $0.formatted() + " Token" } ?? L("未连接"))
    }
}

struct UsageMonthChart: View {
    let history: UsageHistory
    let language: String
    @Environment(\.colorScheme) private var colorScheme
    @State private var selected: Date?
    @State private var hovered: Date?
    private var focus: DailyUsage? {
        history.days.first { $0.date == (hovered ?? selected) } ?? history.days.first(where: \.isToday)
    }
    private var highlight: Color { colorScheme == .light ? Color(red: 0.10, green: 0.36, blue: 0.28) : mint }
    private var locale: Locale { Locale(identifier: language == "en" ? "en_US" : "zh_Hans_CN") }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(L("本月每日")).foregroundStyle(Color.primary.opacity(0.66))
                Spacer(minLength: 4)
                Text(L("峰值") + " " + compact(history.peak)).foregroundStyle(Color.primary.opacity(0.66))
            }.font(.system(size: 10))
            GeometryReader { geometry in
              HStack(alignment: .bottom, spacing: 2) {
                ForEach(history.days) { day in
                    Button { selected = day.date } label: {
                        VStack(spacing: 5) {
                            ZStack(alignment: .bottom) {
                                Color.clear
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(day.date == focus?.date ? highlight : Color.primary.opacity(day.isFuture ? 0.08 : (colorScheme == .light ? 0.48 : 0.38)))
                                    .frame(height: height(day))
                            }.frame(height: 52)
                            Text(label(day)).font(.system(size: 8)).monospacedDigit()
                                .foregroundStyle(day.date == focus?.date ? highlight : Color.primary.opacity(0.66))
                                .fixedSize(horizontal: true, vertical: false).frame(height: 11)
                        }.frame(width: max(1, (geometry.size.width - CGFloat(history.days.count - 1) * 2) / CGFloat(history.days.count))).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).disabled(day.isFuture)
                    .onHover { inside in if !day.isFuture { hovered = inside ? day.date : nil } }
                    .help(dateLabel(day) + " · " + day.tokens.formatted() + " Token")
                    .accessibilityLabel(dateLabel(day))
                    .accessibilityValue(day.tokens.formatted() + " Token")
                    .accessibilityAddTraits(day.date == focus?.date ? .isSelected : [])
                }
              }
            }.frame(height: 68).accessibilityLabel(L("本月每日 Token 柱状图"))
            HStack(spacing: 5) {
                if let day = focus {
                    Text(dateLabel(day)).foregroundStyle(Color.primary.opacity(0.66))
                    Spacer(minLength: 4)
                    Text(day.tokens.formatted() + " Token").monospacedDigit()
                }
            }.font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.85)
            if history.month == 0 {
                Text(L("尚未读取到本月用量")).font(.system(size: 9)).foregroundStyle(Color.primary.opacity(0.66))
            }
        }
        .onChange(of: history.monthStart) { _, _ in selected = nil; hovered = nil }
    }

    private func height(_ day: DailyUsage) -> CGFloat {
        guard day.tokens > 0, history.peak > 0 else { return 1 }
        return max(2, 52 * CGFloat(day.tokens) / CGFloat(history.peak))
    }
    private func label(_ day: DailyUsage) -> String {
        day.day == 1 || day.day % 7 == 0 || day.isToday ? String(day.day) : " "
    }
    private func dateLabel(_ day: DailyUsage) -> String {
        day.date.formatted(.dateTime.month(.twoDigits).day().weekday(.abbreviated).locale(locale))
    }
}
