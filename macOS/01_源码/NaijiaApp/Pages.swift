import SwiftUI
import NaijiaCore


struct CompanionPane: View {
    @ObservedObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Sprite(store: store, file: store.companionFrame.file, animated: true)
                        .id(store.companionFrame.id).transition(.opacity)
                }.frame(width: 84, height: 88)
                    .animation(UIMotion.feedback(reduceMotion), value: store.companionFrame.id)
                    .accessibilityLabel(L("\(store.companion.name)，\(store.companionFrame.name)"))
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 5) {
                        Text(L(store.companion.name)).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        Badge(text: L(store.companion.rarity), color: rarityColor(store.companion.rarity))
                        Spacer(minLength: 0)
                        Menu {
                            ForEach(store.ownedCharacters) { character in
                                Button(L(character.name)) { store.chooseCompanion(character) }
                            }
                        } label: { Text(L("切换")) }
                        .menuStyle(.borderedButton).controlSize(.mini).fixedSize()
                        .tint(.primary).foregroundStyle(.primary)
                        .accessibilityLabel(L("切换伙伴")).help(L("选择已拥有的伙伴"))
                    }
                    Text(L(store.companionFrame.name)).font(.system(size: 11)).foregroundStyle(.secondary)
                    if let next = store.nextCompanionAction {
                        ProgressView(value: Double(store.companionProgress) / Double(next.threshold)).tint(.secondary)
                        Text(L("\(next.frame.name) · 还需 \(compact(next.threshold - store.companionProgress))"))
                            .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    } else {
                        ProgressView(value: 1).tint(.secondary)
                        Text(L("动作已全部解锁")).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }.padding(.top, 3)
            }
            ActionRoute(store: store, character: store.companion, selectedID: store.companionFrame.id) { store.selectAction($0) }
            if store.state.phase == .incubating {
                Divider()
                HStack(spacing: 11) {
                    EggView(grade: store.state.eggGrade)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(L("\(gradeName(store.state.eggGrade))奶蛋")).font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Text(L("\(Int(store.game.eggProgress * 100))%")).font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        ProgressView(value: store.game.eggProgress).tint(.secondary)
                        Text(L("还需 \(compact(store.game.remainingEggTokens)) Token"))
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            } else if store.companion.id != store.active.id {
                Button(L("培养 · \(store.active.name)")) { store.chooseCompanion(store.active) }.buttonStyle(.bordered).controlSize(.small)
            } else if store.nextAction == nil {
                HStack {
                    Text(L("准备孵化下一位伙伴")).font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    Button(L("开始孵蛋")) { store.startNextEgg() }.buttonStyle(.bordered).controlSize(.small)
                }
            }
            Divider()
            UsageStrip(store: store)
        }
    }
}

struct ActionRoute: View {
    @ObservedObject var store: AppStore
    let character: CharacterAsset
    let selectedID: String?
    let onSelect: (FrameAsset) -> Void
    @Namespace private var selection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 4) {
                ForEach(Array(character.orderedFrames.enumerated()), id: \.element.id) { index, frame in
                    let available = store.game.unlocked(frame, character: character)
                    Button { onSelect(frame) } label: {
                        VStack(spacing: 3) {
                            Sprite(store: store, file: frame.file, animated: available && selectedID == frame.id).frame(width: 42, height: 44)
                                .saturation(available ? 1 : 0).opacity(available ? 1 : 0.3)
                            Text(L(frame.name)).font(.system(size: 9)).lineLimit(2).minimumScaleFactor(0.8)
                                .frame(height: 23, alignment: .top).foregroundStyle(available ? .primary : .tertiary)
                            ZStack {
                                if selectedID == frame.id {
                                    if reduceMotion { Circle().fill(.primary) }
                                    else { Circle().fill(.primary).matchedGeometryEffect(id: "selected-action", in: selection) }
                                }
                            }.frame(width: 3, height: 3)
                        }.frame(width: 44).contentShape(Rectangle())
                    }.buttonStyle(SoftPressButtonStyle()).disabled(!available)
                        .accessibilityLabel(L("\(frame.name)，\(available ? "已解锁" : "未解锁")"))
                        .help(L(available ? frame.name : "\(frame.name) · 尚未解锁"))
                    if index < character.orderedFrames.count - 1 {
                        Image(systemName: "chevron.right").font(.system(size: 6)).foregroundStyle(.tertiary)
                            .frame(width: 4, height: 44).accessibilityHidden(true)
                    }
                }
            }
        }.scrollIndicators(.hidden)
            .animation(UIMotion.navigation(reduceMotion), value: selectedID)
    }
}

struct LockedPixel: View {
    var card = false
    // A generic pixel lock conceals the actual asset entirely.
    private let rows = ["00011111000", "00110001100", "01100000110", "01100000110", "01100000110", "11111111111", "11111111111", "11110001111", "11110001111", "11111011111", "11111111111", "11111111111"]
    var body: some View {
        ZStack {
            if card { RoundedRectangle(cornerRadius: 7).fill(.primary.opacity(0.035)).overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.primary.opacity(0.09))) }
            Canvas { context, size in
                let pixel = max(1, floor(min(size.width / 17, size.height / 20)))
                let x = floor((size.width - 11 * pixel) / 2)
                let y = floor((size.height - 12 * pixel) / 2)
                for (row, cells) in rows.enumerated() {
                    for (column, cell) in cells.enumerated() where cell == "1" {
                        context.fill(Path(CGRect(x: x + Double(column) * pixel, y: y + Double(row) * pixel, width: pixel, height: pixel)), with: .color(.secondary.opacity(0.5)))
                    }
                }
            }
        }.accessibilityLabel(L("未解锁"))
    }
}

struct BagPane: View {
    @ObservedObject var store: AppStore
    var onItemsChanged: (Bool) -> Void = { _ in }
    @State private var mode = 0
    @State private var grade = 1
    @State private var page = 0
    @State private var search = ""
    @State private var onlyOwned = false
    @State private var selectedCharacter: CharacterAsset?
    @State private var forwardPage = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init(store: AppStore, onItemsChanged: @escaping (Bool) -> Void = { _ in }, initialMode: Int = 0) {
        self.store = store; self.onItemsChanged = onItemsChanged; _mode = State(initialValue: initialMode)
    }
    private var characters: [CharacterAsset] {
        store.library.characters.filter {
            $0.rarityCode == grade && (!onlyOwned || store.game.owns($0)) &&
            (search.isEmpty || (store.game.owns($0) && ($0.name.localizedCaseInsensitiveContains(search) || L($0.name).localizedCaseInsensitiveContains(search) || ($0.aliases ?? []).contains { $0.localizedCaseInsensitiveContains(search) })))
        }.sorted { store.game.owns($0) == store.game.owns($1) ? $0.id < $1.id : store.game.owns($0) }
    }
    private var cards: [CardAsset] {
        store.library.cards.filter {
            let owned = store.state.collection[$0.id, default: 0] > 0
            return store.library.character($0.characterId)?.rarityCode == grade && (!onlyOwned || owned) &&
                (search.isEmpty || (owned && ($0.name.localizedCaseInsensitiveContains(search) || L($0.name).localizedCaseInsensitiveContains(search) || $0.id.localizedCaseInsensitiveContains(search) || $0.actionName.localizedCaseInsensitiveContains(search) || L($0.actionName).localizedCaseInsensitiveContains(search))))
        }.sorted {
            let firstOwned = store.state.collection[$0.id, default: 0] > 0
            let secondOwned = store.state.collection[$1.id, default: 0] > 0
            return firstOwned == secondOwned ? $0.id < $1.id : firstOwned
        }
    }
    private var capacity: Int { mode == 0 ? 16 : 12 }
    private var itemCount: Int { mode == 0 ? characters.count : cards.count }
    private var pageCount: Int { max(1, (itemCount + capacity - 1) / capacity) }
    private var pageCharacters: [CharacterAsset] { Array(characters.dropFirst(page * capacity).prefix(capacity)) }
    private var pageCards: [CardAsset] { Array(cards.dropFirst(page * capacity).prefix(capacity)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let character = selectedCharacter {
                CharacterDetail(store: store, character: character, onBack: { selectedCharacter = nil })
                    .transition(UIMotion.page(reduced: reduceMotion))
            } else {
              VStack(alignment: .leading, spacing: 10) {
                Picker(L("背包类别"), selection: Binding(get: { mode }, set: { next in forwardPage = next >= mode; mode = next })) { Text(L("伙伴")).tag(0); Text(L("卡片")).tag(1); Text(L("道具")).tag(2) }
                    .pickerStyle(.segmented).labelsHidden()
                if mode == 2 { InventoryPane(store: store).transition(.opacity) }
                else {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(L("搜索"), text: $search).textFieldStyle(.plain).font(.system(size: 11))
                        .help(L("搜索已拥有的伙伴和卡片"))
                    if !search.isEmpty { IconButton(symbol: "xmark.circle.fill", label: L("清空搜索")) { search = "" } }
                }.padding(.horizontal, 8).padding(.vertical, 5)
                    .background(.secondary.opacity(0.025), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.2)))
                HStack {
                    Text(L(mode == 0 ? "伙伴 \(store.ownedCharacters.count) / \(store.library.characters.count)" : "卡片 \(store.distinctCards) / \(store.library.cards.count)"))
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Toggle(L("已拥有"), isOn: $onlyOwned).toggleStyle(.checkbox).font(.system(size: 10))
                }
                HStack(spacing: 5) {
                    ForEach(1...4, id: \.self) { rarity in
                        rarityFilter(rarity)
                    }
                }
                if itemCount == 0 {
                    VStack(spacing: 8) {
                        Text(L(search.isEmpty ? "暂无物品" : "没有匹配的伙伴或卡片"))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        if !search.isEmpty || onlyOwned {
                            Button(L("清除筛选")) { search = ""; onlyOwned = false }.buttonStyle(.bordered).controlSize(.small)
                        }
                    }.frame(maxWidth: .infinity).padding(.vertical, 24)
                } else {
                  ZStack(alignment: .topLeading) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 4), spacing: 7) {
                        if mode == 0 {
                            ForEach(pageCharacters) { character in characterCell(character) }
                        } else {
                            ForEach(pageCards) { card in cardCell(card) }
                        }
                    }
                    .id("\(mode)-\(grade)-\(page)")
                    .transition(UIMotion.page(forward: forwardPage, reduced: reduceMotion))
                  }
                    HStack(spacing: 9) {
                        Spacer()
                        Button { forwardPage = false; page -= 1 } label: { Image(systemName: "chevron.left") }
                            .disabled(page == 0).accessibilityLabel(L("上一页"))
                        Text(L("\(page + 1) / \(pageCount)")).monospacedDigit().foregroundStyle(.secondary)
                        Button { forwardPage = true; page += 1 } label: { Image(systemName: "chevron.right") }
                            .disabled(page + 1 >= pageCount).accessibilityLabel(L("下一页"))
                    }.buttonStyle(.plain).font(.system(size: 11)).padding(.top, 3)
                }
                }
              }.transition(UIMotion.page(forward: false, reduced: reduceMotion))
            }
        }
        .animation(UIMotion.detail(reduceMotion), value: selectedCharacter?.id)
        .animation(UIMotion.navigation(reduceMotion), value: mode)
        .animation(UIMotion.navigation(reduceMotion), value: grade)
        .animation(UIMotion.navigation(reduceMotion), value: page)
        .animation(UIMotion.feedback(reduceMotion), value: onlyOwned)
        .onAppear { onItemsChanged(mode == 2) }
        .onChange(of: mode) { _, _ in page = 0; onItemsChanged(mode == 2) }
        .onChange(of: grade) { _, _ in page = 0 }
        .onChange(of: search) { _, _ in page = 0 }
        .onChange(of: onlyOwned) { _, _ in page = 0 }
        .onChange(of: pageCount) { _, count in page = min(page, count - 1) }
    }

    private func rarityFilter(_ rarity: Int) -> some View {
        let characterGroup = store.library.characters.filter { $0.rarityCode == rarity }
        let cardGroup = store.library.cards.filter { store.library.character($0.characterId)?.rarityCode == rarity }
        let owned = mode == 0 ? characterGroup.filter { store.game.owns($0) }.count : cardGroup.filter { store.state.collection[$0.id, default: 0] > 0 }.count
        let total = mode == 0 ? characterGroup.count : cardGroup.count
        let color = rarityColor(gradeName(rarity))
        return Button { forwardPage = rarity >= grade; grade = rarity } label: {
            HStack(spacing: 3) {
                Circle().fill(color).frame(width: 4, height: 4)
                Text(L(gradeName(rarity)))
                Text(L("\(owned)/\(total)")).monospacedDigit()
            }.font(.system(size: 9, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity).padding(.vertical, 5)
                .background(color.opacity(grade == rarity ? 0.12 : 0.035), in: Capsule())
                .overlay(Capsule().strokeBorder(color.opacity(grade == rarity ? 0.45 : 0.13), lineWidth: 0.5))
        }.buttonStyle(SoftPressButtonStyle()).accessibilityLabel(L("\(gradeName(rarity))，\(owned) / \(total)"))
            .accessibilityAddTraits(grade == rarity ? .isSelected : [])
    }

    private func characterCell(_ character: CharacterAsset) -> some View {
        let owned = store.game.owns(character)
        return Button { selectedCharacter = character } label: {
            VStack(spacing: 3) {
                HStack { Text(L(owned ? character.id : "")).font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary); Spacer() }.frame(height: 9)
                if owned { Sprite(store: store, file: character.idle.file).frame(height: 44) }
                else { LockedPixel().frame(height: 44) }
                Text(L(owned ? character.name : "")).font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.8).frame(height: 12)
            }.frame(height: 70).padding(5).frame(maxWidth: .infinity)
                .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(SoftPressButtonStyle()).disabled(!owned)
            .accessibilityLabel(L(owned ? "\(character.name)，已拥有" : "未解锁伙伴"))
    }

    private func cardCell(_ card: CardAsset) -> some View {
        let count = store.state.collection[card.id, default: 0]
        return Button { store.selectedCard = card } label: {
            Group {
                if count > 0 {
                    Sprite(store: store, file: card.file, thumbnailMaxPixelSize: 320).aspectRatio(2 / 3, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay(alignment: .topTrailing) {
                            Text(L("×\(count)")).font(.system(size: 8)).padding(3)
                                .background(.black.opacity(0.7), in: Capsule()).foregroundStyle(.white).padding(3)
                        }
                } else { LockedPixel(card: true).aspectRatio(2 / 3, contentMode: .fit) }
            }
        }.buttonStyle(SoftPressButtonStyle()).disabled(count == 0)
            .accessibilityLabel(L(count > 0 ? "\(card.name)，\(card.actionName)，\(card.id)" : "未解锁卡片"))
            .help(L(count > 0 ? "\(card.name) · \(card.actionName)" : "未解锁"))
    }
}

struct CharacterDetail: View {
    @ObservedObject var store: AppStore
    let character: CharacterAsset
    let onBack: () -> Void
    @State private var selectedFrame: FrameAsset?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: onBack) { Label(L("背包"), systemImage: "chevron.left") }.buttonStyle(.plain).foregroundStyle(.secondary)
            ZStack {
                Sprite(store: store, file: (selectedFrame ?? character.idle).file, animated: true)
                    .id((selectedFrame ?? character.idle).id).transition(.opacity)
            }.frame(height: 155).frame(maxWidth: .infinity)
                .animation(UIMotion.feedback(reduceMotion), value: selectedFrame?.id)
            HStack { Text(L(character.name)).font(.system(size: 16, weight: .semibold)); Badge(text: L(character.rarity), color: rarityColor(character.rarity)); Spacer() }
            SectionCaption(text: L("动作"))
            ActionRoute(store: store, character: character, selectedID: (selectedFrame ?? character.idle).id) { selectedFrame = $0 }
            Button { store.displayOnDesktop(character, frame: selectedFrame) } label: { Text(L("设为伙伴")).frame(maxWidth: .infinity) }.buttonStyle(.bordered).controlSize(.small)
            if let id = (selectedFrame ?? character.idle).cardId, store.state.collection[id, default: 0] > 0, let card = store.library.card(id) {
                Button(L("查看卡片")) { store.selectedCard = card }.buttonStyle(.bordered)
            }
        }
    }
}

struct SettingsPane: View {
    @ObservedObject var store: AppStore
    let onOpenDeveloper: () -> Void
    @State private var difficultyDraft = 100.0
    @State private var difficultyTask: Task<Void, Never>?
    @State private var difficultyEditing = false
    @State private var petSizeDraft = 116.0
    @State private var petSizeEditing = false
    @State private var petSizeTask: Task<Void, Never>?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionCaption(text: L("桌面与外观"))
            Toggle(L("桌面伙伴"), isOn: Binding(get: { store.state.desktopVisible }, set: { store.preference(\.desktopVisible, $0) })).toggleStyle(.switch).controlSize(.small)
            Toggle(L("固定浮窗"), isOn: Binding(get: { store.state.pinned }, set: { store.preference(\.pinned, $0) })).toggleStyle(.switch).controlSize(.small)
            HStack { Text(L("外观")); Spacer(); Picker(L("外观"), selection: Binding(get: { store.state.appearance }, set: { store.preference(\.appearance, $0) })) { Text(L("跟随系统")).tag("system"); Text(L("浅色")).tag("light"); Text(L("深色")).tag("dark") }.labelsHidden().frame(width: 135) }
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text(L("伙伴大小")); Spacer(); Text(L("\(Int(petSizeDraft)) px")).foregroundStyle(.secondary) }
                Slider(value: $petSizeDraft, in: 80...180, step: 4) { editing in
                    petSizeEditing = editing
                    if !editing { commitPetSize() }
                }.accessibilityLabel(L("伙伴大小"))
            }
            Button(L("将伙伴移回屏幕")) { store.onResetDesktopPosition?() }.buttonStyle(.bordered).controlSize(.small)
            Divider()
            SectionCaption(text: L("玩法"))
            VStack(alignment: .leading, spacing: 6) {
                HStack { Text(L("难度")); Spacer(); Text(L("\(Int(difficultyDraft))%")).monospacedDigit().foregroundStyle(.secondary) }
                Slider(value: Binding(get: { DifficultyScale.position(for: difficultyDraft) }, set: { difficultyDraft = DifficultyScale.percent(at: $0).rounded() }), in: 0...1) { editing in
                    difficultyEditing = editing
                    if !editing { store.changeDifficulty(Int(difficultyDraft.rounded())) }
                }.accessibilityLabel(L("难度")).accessibilityValue("\(Int(difficultyDraft))%")
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        Text("20%").frame(maxWidth: .infinity, alignment: .leading)
                        Button("100%") { difficultyDraft = 100; store.changeDifficulty(100) }
                            .buttonStyle(.plain).help(L("难度") + " · 100%")
                            .position(x: 7 + (geometry.size.width - 14) * 0.2, y: 6)
                        Text("500%").frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }.frame(height: 14).font(.system(size: 10)).foregroundStyle(.secondary)
                Text(L("培养、孵化所需 Token 和商品价格按比例调整。数值越低，成长越快、商品越便宜。"))
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text(L("语言")); Spacer()
                Picker(L("语言"), selection: Binding(get: { store.state.language ?? "zh-Hans" }, set: { store.preference(\.language, Optional($0)) })) {
                    Text(L("中文")).tag("zh-Hans"); Text(L("English")).tag("en")
                }.labelsHidden().frame(width: 135)
            }
            Divider()
            #if DEBUG
            if store.developerToolsAvailable {
                Button(action: onOpenDeveloper) { Label(L("开发工具"), systemImage: "wrench.and.screwdriver") }.buttonStyle(.bordered).help(L("在独立测试存档中修改 Token 或重置进度"))
                Divider()
            }
            #endif
            Group {
                SectionCaption(text: L("用量"))
                HStack { Text(L("累计成长")); Spacer(); Text(L("\(compact(store.state.totalTokens)) Token")).monospacedDigit() }.font(.system(size: 11))
                ForEach(store.usageSnapshot?.providers ?? [], id: \.provider) { usage in
                    HStack { Text(L(usage.provider == .codex ? "Codex" : "Claude Code")); Spacer(); Text(L(usage.error != nil ? "异常" : (usage.files > 0 ? "已连接" : "未连接"))).foregroundStyle(.secondary) }.font(.system(size: 10)).help(L("\(usage.files) 份本机日志"))
                }
                if let error = store.usageError { Text(L(error)).font(.system(size: 10)).foregroundStyle(.orange) }
                HStack { Button(L("刷新")) { Task { await store.refreshUsage() } }.disabled(store.usageReading); Button(L("Codex…")) { store.chooseUsageFolder(.codex) }.help(L("选择 Codex 日志文件夹")); Button(L("Claude…")) { store.chooseUsageFolder(.claude) }.help(L("选择 Claude Code 日志文件夹")) }.buttonStyle(.bordered).controlSize(.small)
                Text(L("每 15 秒同步 · 仅新增用量计入成长")).font(.system(size: 10)).foregroundStyle(.secondary)
                    .help(L("历史用量只作统计；重启不重复奖励，缓存已包含在 Token 合计内"))
            }
            Button(L("读取素材")) { store.reloadAssets() }.buttonStyle(.bordered)
            Button(L("使用与隐私说明")) { store.openHelp() }.buttonStyle(.plain).foregroundStyle(.secondary)
            Divider()
            Text(L("\(ApplicationIdentity.displayName) · \(ApplicationIdentity.version)")).font(.system(size: 10)).foregroundStyle(.tertiary)
        }.onAppear { difficultyDraft = Double(store.game.difficulty); petSizeDraft = store.state.petSize }
            .onChange(of: store.state.petSize) { _, value in petSizeDraft = value }
            .onChange(of: store.game.difficulty) { _, value in difficultyDraft = Double(value) }
            .onChange(of: difficultyDraft) { _, value in
                difficultyTask?.cancel()
                guard !difficultyEditing else { return }
                difficultyTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(180))
                    guard !Task.isCancelled else { return }
                    store.changeDifficulty(Int(value.rounded()))
                }
            }
            .onChange(of: petSizeDraft) { _, _ in
                petSizeTask?.cancel()
                guard !petSizeEditing else { return }
                petSizeTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(180))
                    guard !Task.isCancelled else { return }
                    commitPetSize()
                }
            }
            .onDisappear {
                difficultyTask?.cancel(); petSizeTask?.cancel()
                store.changeDifficulty(Int(difficultyDraft.rounded()))
                commitPetSize()
            }
    }

    private func commitPetSize() {
        guard petSizeDraft != store.state.petSize else { return }
        store.preference(\.petSize, petSizeDraft)
    }
}
