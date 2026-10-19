import AppKit
import SwiftUI
import NaijiaCore

let mint = Color(red: 0.49, green: 0.84, blue: 0.73)

enum PanelMetrics {
    static let width: CGFloat = 360
    static let height: CGFloat = 620
    static let padding: CGFloat = 14
    static let contentWidth = width - padding * 2
}

enum MainTab: String, CaseIterable, Identifiable {
    case companion = "伙伴", collection = "背包", shop = "小铺"
    var id: String { rawValue }
}

struct PanelRoot: View {
    @ObservedObject var store: AppStore
    let onClose: () -> Void
    let onHeightChanged: (CGFloat) -> Void
    @State private var tab = MainTab.companion
    @State private var settings = false
    @State private var developerTools = false
    @State private var bagItems = false
    @State private var cardSamples = false
    @State private var forwardNavigation = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(store: AppStore, onClose: @escaping () -> Void, onHeightChanged: @escaping (CGFloat) -> Void,
         initialTab: MainTab = .companion, initialSettings: Bool = false) {
        self.store = store; self.onClose = onClose; self.onHeightChanged = onHeightChanged
        _tab = State(initialValue: initialTab); _settings = State(initialValue: initialSettings)
    }

    private var pageID: String {
        if cardSamples { return "samples" }
        if settings { return developerTools ? "developer" : "settings" }
        if store.onboardingStage == .choosePartner { return "starter" }
        return tab.rawValue
    }

    private var tabSelection: Binding<MainTab> {
        Binding(get: { tab }, set: { next in
            forwardNavigation = MainTab.allCases.firstIndex(of: next)! >= MainTab.allCases.firstIndex(of: tab)!
            tab = next; store.selectedCard = nil
        })
    }

    private var preferredHeight: CGFloat {
        if settings || cardSamples { return 620 }
        if store.onboardingStage == .choosePartner || store.selectedCard != nil { return 620 }
        switch tab {
        case .companion: return 620
        case .collection: return bagItems ? 380 : 620
        case .shop: return 480
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if settings { header }
            if !settings && !cardSamples && store.onboardingStage != .choosePartner {
                Picker(L("页面"), selection: tabSelection) {
                    ForEach(MainTab.allCases) { Text(L($0.rawValue)).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                .padding(.horizontal, PanelMetrics.padding).padding(.top, 14).padding(.bottom, 12)
                .onChange(of: tab) { _, _ in store.selectedCard = nil }
            }
            ZStack(alignment: .topLeading) {
              ScrollView {
                Group {
                    if cardSamples {
                        #if DEBUG
                        CardSamplesPane(store: store, onClose: { cardSamples = false })
                        #endif
                    } else if settings {
                        #if DEBUG
                        if developerTools { DevelopmentPane(store: store, onReview: { settings = false; developerTools = false; tab = .companion }) }
                        else { SettingsPane(store: store, onOpenDeveloper: { developerTools = true }) }
                        #else
                        SettingsPane(store: store, onOpenDeveloper: {})
                        #endif
                    }
                    else if store.onboardingStage == .choosePartner { StarterSelectionPane(store: store) }
                    else {
                        ZStack(alignment: .topLeading) {
                            VStack(alignment: .leading, spacing: 12) {
                                if store.onboardingStage == .starterCard && tab != .shop {
                                    StarterShopGuide { tab = .shop; store.selectedCard = nil }
                                }
                                switch tab {
                                case .companion: CompanionPane(store: store)
                                case .collection: BagPane(store: store, onItemsChanged: { bagItems = $0 })
                                case .shop: ShopPane(store: store)
                                }
                            }
                            .opacity(store.selectedCard == nil ? 1 : 0)
                            .offset(y: store.selectedCard == nil || reduceMotion ? 0 : -4)
                            .allowsHitTesting(store.selectedCard == nil)
                            .accessibilityHidden(store.selectedCard != nil)
                            if let card = store.selectedCard {
                                CardDetail(store: store, card: card)
                                    .id(card.id)
                                    .transition(UIMotion.pop(reduced: reduceMotion))
                            }
                        }
                        .animation(UIMotion.detail(reduceMotion), value: store.selectedCard?.id)
                    }
                }
                .frame(width: PanelMetrics.contentWidth, alignment: .leading)
                .padding(.horizontal, PanelMetrics.padding).padding(.bottom, 12)
                .padding(.top, store.onboardingStage == .choosePartner && !settings ? 14 : 0)
            }
            .scrollIndicators(.automatic)
              .id(pageID)
              .transition(UIMotion.page(forward: forwardNavigation, reduced: reduceMotion))
            }
            .animation(UIMotion.navigation(reduceMotion), value: pageID)
            footer
        }
        .frame(width: PanelMetrics.width).frame(maxHeight: .infinity, alignment: .top)
        .background(GlassSurface())
        .overlay(alignment: .bottom) {
            if let toast = store.toast {
                Text(L(toast)).font(.system(size: 11, weight: .medium))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
                    .padding(.horizontal, 20).padding(.bottom, 42)
                    .id(toast)
                    .transition(UIMotion.toast(reduced: reduceMotion))
                    .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
        .tint(.primary)
        .font(.system(size: 12))
        .animation(UIMotion.navigation(reduceMotion), value: store.toast)
        .preferredColorScheme(store.state.appearance == "system" ? nil : (store.state.appearance == "light" ? .light : .dark))
        .environment(\.locale, Locale(identifier: store.state.language ?? "zh-Hans"))
        .id(store.state.language ?? "zh-Hans")
        .onAppear { onHeightChanged(preferredHeight) }
        .onChange(of: preferredHeight) { _, height in onHeightChanged(height) }
        .onChange(of: store.onboardingStage) { _, stage in
            if stage == .choosePartner || stage == .starterCard {
                settings = false; developerTools = false; tab = .companion
            }
        }
        .onExitCommand { if cardSamples { cardSamples = false } else if developerTools { developerTools = false } else if settings { settings = false } else if store.selectedCard != nil { store.selectedCard = nil } else { onClose() } }
    }

    private var header: some View {
        HStack(spacing: 8) {
            IconButton(symbol: "chevron.left", label: L("返回")) {
                if developerTools { developerTools = false } else { settings.toggle() }
                store.selectedCard = nil
            }
            Text(L(developerTools ? "开发工具" : "设置")).font(.system(size: 13, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, PanelMetrics.padding).padding(.top, 12).padding(.bottom, 12)
    }

    private var footer: some View {
        HStack(spacing: 5) {
            #if DEBUG
            Button(L("样卡")) { cardSamples = true; settings = false; developerTools = false; store.selectedCard = nil }.buttonStyle(.plain).help(L("直接审查全部闪光、黑金和幻影卡"))
            if store.developmentTesting {
                Button {
                    settings = true; developerTools = true; store.selectedCard = nil
                } label: { Label(L("测试"), systemImage: "wrench") }
                .buttonStyle(.plain).help(L("打开开发工具；真实成长已暂停"))
            } else { syncStatus }
            #else
            syncStatus
            #endif
            Spacer(minLength: 0)
            IconButton(symbol: store.state.pinned ? "pin.fill" : "pin", label: L(store.state.pinned ? "取消固定浮窗" : "固定浮窗")) {
                store.preference(\.pinned, !store.state.pinned)
            }
            IconButton(symbol: store.state.desktopVisible ? "pawprint.fill" : "pawprint", label: L(store.state.desktopVisible ? "隐藏桌面伙伴" : "显示桌面伙伴")) {
                store.preference(\.desktopVisible, !store.state.desktopVisible)
            }
            IconButton(symbol: "gearshape", label: L("偏好设置")) {
                cardSamples = false; settings.toggle(); developerTools = false; store.selectedCard = nil
            }
            IconButton(symbol: "xmark", label: L("收起\(ApplicationIdentity.displayName)")) { onClose() }
        }
        .font(.system(size: 10)).foregroundStyle(.secondary)
        .padding(.horizontal, PanelMetrics.padding).padding(.vertical, 9)
    }

    private var syncStatus: some View {
        HStack(spacing: 5) {
            IconButton(symbol: "arrow.clockwise", label: L("刷新真实用量")) { Task { await store.refreshUsage() } }
                .disabled(store.usageReading)
            Button(L(store.usageStatusText)) { settings = true; developerTools = false; store.selectedCard = nil }
                .buttonStyle(.plain)
                .foregroundStyle(store.usageError == nil ? Color.secondary : Color.orange)
                .help(L(store.usageError ?? "每 15 秒自动同步 Codex 与 Claude Code 本机日志"))
        }
    }
}

struct GlassSurface: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        if reduceTransparency { Color(nsColor: .windowBackgroundColor) }
        else { GlassBackground().overlay(colorScheme == .dark ? Color.black.opacity(0.45) : Color.white.opacity(0.12)) }
    }
}

struct GlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct IconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 12, weight: .medium)).frame(width: 22, height: 22).contentShape(Rectangle()) }
            .buttonStyle(SoftPressButtonStyle())
            .background(.primary.opacity(hovering ? 0.07 : 0), in: RoundedRectangle(cornerRadius: 5))
            .onHover { hovering = $0 }
            .animation(UIMotion.feedback(reduceMotion), value: hovering)
            .help(L(label)).accessibilityLabel(L(label))
    }
}

struct Sprite: View {
    @ObservedObject var store: AppStore
    let file: String
    var animated = false
    var thumbnailMaxPixelSize: Int? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Group {
            if animated, let animation = store.animation(for: file) {
                AnimatedSprite(store: store, animation: animation)
                    .id(store.projectRoot.path + file)
            } else { artwork(file) }
        }
    }
    @ViewBuilder private func artwork(_ path: String) -> some View {
        if let image = store.image(path, thumbnailMaxPixelSize: thumbnailMaxPixelSize) { Image(nsImage: image).resizable().interpolation(.none).scaledToFit() }
        else { Image(systemName: "questionmark.square.dashed").foregroundStyle(.secondary).padding(16).accessibilityLabel(L(store.t("素材未找到"))) }
    }
}

private struct AnimatedSprite: View {
    @ObservedObject var store: AppStore
    let animation: AnimationAsset
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var clock = AnimationPlaybackClock()
    @State private var finished = false
    private var playing: Bool { appeared && store.panelVisible && store.selectedCard == nil && !reduceMotion && !finished }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15, paused: !playing)) { timeline in
            let elapsed = clock.elapsed(at: timeline.date)
            let index = reduceMotion ? 0 : animation.frameIndex(elapsed: elapsed)
            Sprite(store: store, file: animation.frames[index].file)
                .onChange(of: timeline.date) { _, date in
                    if !animation.loop, clock.elapsed(at: date) >= Double(animation.frameDurationsMs.reduce(0, +)) / 1000 {
                        finished = true
                    }
                }
        }
        .onAppear { appeared = true; clock.setPlaying(playing, at: Date()) }
        .onDisappear { appeared = false; clock.setPlaying(false, at: Date()) }
        .onChange(of: playing) { _, value in clock.setPlaying(value, at: Date()) }
    }
}

struct Badge: View {
    let text: String
    var color = Color.secondary
    var body: some View {
        Text(L(text)).font(.system(size: 10, weight: .semibold)).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 3).background(color.opacity(0.12), in: Capsule())
    }
}

struct SectionCaption: View {
    let text: String
    var trailing: String? = nil
    var body: some View {
        HStack {
            Text(L(text)).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            Spacer()
            if let trailing { Text(L(trailing)).font(.system(size: 10)).foregroundStyle(.tertiary) }
        }
    }
}

struct CardDetail: View {
    @ObservedObject var store: AppStore
    let card: CardAsset
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Button { store.selectedCard = nil } label: { Label(L("返回"), systemImage: "chevron.left") }.buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                Text(L("×\(store.state.collection[card.id, default: 0])")).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }
            InteractiveCard(store: store, card: card)
            HStack { Text(L(card.actionName)).font(.system(size: 11)).foregroundStyle(.secondary); Spacer() }
            Button(L("原图")) {
                NSWorkspace.shared.open(store.projectRoot.appendingPathComponent(card.file))
            }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(mint).help(L("打开 \(card.id) 原尺寸卡面"))
        }
    }
}

struct DrawButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isEnabled ? Color.black.opacity(0.8) : Color.secondary)
            .padding(.vertical, 5)
            .background(isEnabled ? Color.white.opacity(configuration.isPressed ? 0.8 : 1) : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
            .scaleEffect(configuration.isPressed && isEnabled && !reduceMotion ? 0.98 : 1)
            .animation(UIMotion.feedback(reduceMotion), value: configuration.isPressed)
    }
}

struct ShopPane: View {
    @ObservedObject var store: AppStore
    @State private var drawing = false
    @State private var drawTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("奶币")).foregroundStyle(.secondary)
                Spacer()
                Text(L(store.state.coins.formatted())).font(.system(size: 24, weight: .bold)).monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L("抽卡")).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(L("\(L("免费次数")) · \(store.state.freeDraws)")).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                if store.onboardingStage == .starterCard {
                    Text(L("\(store.t(store.active.name)) · \(L("领取待机卡"))")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                if drawing {
                    ZStack { LockedPixel(card: true).frame(width: 38, height: 56); PixelSparkles(active: true) }
                        .frame(height: 60).frame(maxWidth: .infinity).accessibilityLabel(L("正在抽卡"))
                        .transition(UIMotion.pop(reduced: reduceMotion))
                }
                Button { beginDraw() } label: { Text(L("免费抽卡")).frame(maxWidth: .infinity) }
                    .buttonStyle(DrawButtonStyle()).disabled(drawing || store.state.freeDraws == 0 || store.availableCards.isEmpty)
                Text(L("仅可抽取已解锁动作的卡牌")).font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(10).background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                .animation(UIMotion.navigation(reduceMotion), value: drawing)
            ForEach(InventoryItem.allCases) { item in
                HStack(spacing: 9) {
                    Sprite(store: store, file: item.imagePath).frame(width: 42, height: 44).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L(store.t(item.name))).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Text(L(itemDescription(item))).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 3)
                    VStack(spacing: 4) {
                        Text(L("\(store.game.price(item)) \(L("奶币"))")).font(.system(size: 9)).foregroundStyle(.secondary)
                        Button(L("购买")) { store.buy(item) }.buttonStyle(.bordered).controlSize(.small)
                            .disabled(!store.game.readyForGrowth || store.state.coins < store.game.price(item))
                    }
                }.padding(.vertical, 5)
                if item != InventoryItem.allCases.last { Divider() }
            }
            Text(L("购买后存入背包")).font(.system(size: 10)).foregroundStyle(.secondary)
        }.onDisappear { drawTask?.cancel(); drawing = false }
    }

    private func beginDraw() {
        guard !drawing else { return }
        drawing = true
        drawTask = Task { @MainActor in
            if !reduceMotion { try? await Task.sleep(for: .milliseconds(650)) }
            guard !Task.isCancelled else { return }
            store.draw(free: true); drawing = false
        }
    }
}

@MainActor
func itemDescription(_ item: InventoryItem) -> String {
    switch item {
    case .milkCandy: L("孵化进度 +150 Token")
    case .milkStar: L("奶蛋升一级 · 成功率30%")
    case .milkTicket: L("抽取一张已解锁动作卡")
    }
}

struct InventoryPane: View {
    @ObservedObject var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(InventoryItem.allCases) { item in
                HStack(spacing: 10) {
                    Sprite(store: store, file: item.imagePath).frame(width: 46, height: 46).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L(store.t(item.name))).fontWeight(.semibold)
                        Text(L(itemDescription(item))).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 2)
                    VStack(spacing: 5) {
                        Text(L("×\(store.game.count(item))")).monospacedDigit().foregroundStyle(.secondary)
                        Button(L("使用")) { store.use(item) }.buttonStyle(.bordered).controlSize(.small)
                            .disabled(!store.game.canUse(item, library: store.library))
                            .help(L(itemHelp(item)))
                    }
                }
                if item != InventoryItem.allCases.last { Divider() }
            }
            if InventoryItem.allCases.allSatisfy({ store.game.count($0) == 0 }) {
                Text(L("没有可用道具")).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }.padding(.top, 8)
    }
    private func itemHelp(_ item: InventoryItem) -> String {
        if item == .milkCandy && store.game.canUse(item, library: store.library) { return L("仅增加孵化进度，不计入真实 Token 用量。") }
        if store.game.count(item) == 0 { return L("仓库里没有这件道具") }
        if !store.game.readyForGrowth { return L("先领取待机卡") }
        if item == .milkStar && store.state.eggGrade == 4 { return L("已达最高等级") }
        return item == .milkTicket ? itemDescription(item) : L("孵化时可用")
    }
}

func gradeName(_ grade: Int) -> String { [1: "普通", 2: "稀有", 3: "史诗", 4: "传说"][grade] ?? "普通" }

struct EggView: View {
    let grade: Int
    private let rows = [
        "000000###000000", "00000#hhh#00000", "0000#hhhoo#0000", "000#hhhoooo#000",
        "000#hhooooo#000", "00#hhooooooo#00", "00#hoooossoo#00", "0#hoooossssoo#0",
        "0#hoooossssoo#0", "0#hooooossooo#0", "#hoooooooooooo#", "#hoooooooooooo#",
        "#hoossoooooooo#", "#oosssssoooooo#", "#oosssssoooooo#", "0#oossssooooo#0",
        "0#ooossoooooo#0", "00#ooooooooo#00", "000#ooooooo#000", "0000#######0000"
    ]
    var body: some View {
        Canvas { context, size in
            let pixel = max(1, floor(min(size.width / 15, size.height / 20)))
            let x = floor((size.width - 15 * pixel) / 2)
            let y = floor((size.height - 20 * pixel) / 2)
            for (row, cells) in rows.enumerated() {
                for (column, cell) in cells.enumerated() where cell != "0" {
                    let color: Color
                    switch cell {
                    case "#": color = Color(red: 0.39, green: 0.3, blue: 0.17)
                    case "h": color = Color(red: 1, green: 0.97, blue: 0.83)
                    case "s": color = Color(red: 0.76, green: 0.57, blue: 0.22)
                    default: color = Color(red: 0.97, green: 0.86, blue: 0.53)
                    }
                    context.fill(Path(CGRect(x: x + Double(column) * pixel, y: y + Double(row) * pixel, width: pixel, height: pixel)), with: .color(color))
                }
            }
        }.frame(width: 52, height: 64).accessibilityLabel(L("\(gradeName(grade))奶蛋"))
    }
}
