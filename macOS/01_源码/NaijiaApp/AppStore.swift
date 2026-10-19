import AppKit
import Combine
import ImageIO
import NaijiaCore

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var game: DemoGame
    @Published private(set) var library: AssetLibrary
    @Published var toast: String?
    @Published var selectedCard: CardAsset?
    @Published var panelVisible = false
    @Published private(set) var projectRoot: URL
    let primarySaveURL: URL
    #if DEBUG
    var saveURL: URL { developmentTesting ? developmentSaveURL : primarySaveURL }
    var developmentSaveURL: URL { primarySaveURL.deletingLastPathComponent().appendingPathComponent("开发测试存档.json") }
    @Published var developmentTesting = false
    @Published var developerBusy = false
    @Published var developmentUndoState: DemoState?
    #else
    var saveURL: URL { primarySaveURL }
    var developmentTesting: Bool { false }
    var developerBusy: Bool { false }
    #endif
    var developerToolsAvailable: Bool {
        #if DEBUG
        Bundle.main.object(forInfoDictionaryKey: "NaijiaDevelopmentToolsEnabled") as? Bool == true
        #else
        false
        #endif
    }
    var onPreferencesChanged: (() -> Void)?
    var onUsageChanged: (() -> Void)?
    var onResetDesktopPosition: (() -> Void)?
    private let imageCache = NSCache<NSString, NSImage>()
    private var animationCache: [String: AnimationAsset] = [:]
    private var unavailableAnimations = Set<String>()
    private var toastTask: Task<Void, Never>?
    private var usageTask: Task<Void, Never>?
    @Published private(set) var usageSnapshot: UsageSnapshot?
    @Published private(set) var usageReading = false
    @Published private(set) var usageError: String?
    let usageScanner: LocalUsageScanner
    var usageGeneration = 0
    private var extraUsageRoots: [UsageProvider: [URL]] = [:]

    init(projectRoot: URL, saveDirectory: URL? = nil) throws {
        self.projectRoot = projectRoot
        let loadedLibrary = try AssetLibrary.load(from: projectRoot.appendingPathComponent("05_配置与索引/角色记录.json"))
        library = loadedLibrary
        let rulesName = "正式版规则.json"
        let rules = try PreviewRules.load(from: projectRoot.appendingPathComponent("07_软件开发/macOS/02_配置/\(rulesName)"))
        let dataRoot = try saveDirectory ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(ApplicationIdentity.dataDirectory, isDirectory: true)
        primarySaveURL = dataRoot.appendingPathComponent("正式存档.json")
        usageScanner = LocalUsageScanner(cacheURL: dataRoot.appendingPathComponent("用量元数据缓存.json"))
        let state: DemoState
        if FileManager.default.fileExists(atPath: primarySaveURL.path) {
            state = try GameSaveFile.read(from: primarySaveURL, library: loadedLibrary)
        } else { state = DemoState.liveInitial() }
        game = DemoGame(state: state, rules: rules)
        UIStrings.language = game.state.language ?? "zh-Hans"
        if game.state.usageLedger == nil { game.state.usageLedger = UsageLedger() }
        imageCache.totalCostLimit = 48 * 1024 * 1024
        if let data = UserDefaults.standard.data(forKey: "extraUsageRoots"),
           let decoded = try? JSONDecoder().decode([UsageProvider: [URL]].self, from: data) { extraUsageRoots = decoded }
        #if DEBUG
        restoreDevelopmentIfNeeded()
        #endif
    }

    var state: DemoState { game.state }
    var active: CharacterAsset { library.character(state.activeCharacterId)! }
    var desktopCharacter: CharacterAsset { library.character(state.desktopCharacterId) ?? active }
    var currentFrame: FrameAsset { active.orderedFrames.first { $0.id == state.selectedActionId && game.unlocked($0, character: active) } ?? active.idle }
    var desktopFrame: FrameAsset { desktopCharacter.orderedFrames.first { $0.id == state.desktopActionId && game.unlocked($0, character: desktopCharacter) } ?? desktopCharacter.idle }
    var nextAction: (frame: FrameAsset, threshold: Int)? {
        for (index, frame) in active.orderedFrames.enumerated() {
            let threshold = game.threshold(at: index)
            if !game.unlocked(frame, character: active) { return (frame, threshold) }
        }
        return nil
    }
    var unlockedCount: Int { active.orderedFrames.filter { game.unlocked($0, character: active) }.count }
    var distinctCards: Int { state.collection.values.filter { $0 > 0 }.count }
    var ownedCharacters: [CharacterAsset] { library.characters.filter { game.owns($0) } }
    var availableCards: [CardAsset] { game.eligibleCards(in: library) }
    var starterChoices: [CharacterAsset] { library.characters.filter { $0.rarityCode == 1 }.sorted { $0.id < $1.id } }
    var onboardingStage: OnboardingStage { game.onboardingStage }
    var companion: CharacterAsset { desktopCharacter }
    var companionFrame: FrameAsset { desktopFrame }
    var companionProgress: Int { game.progress(for: companion) }
    var nextCompanionAction: (frame: FrameAsset, threshold: Int)? {
        for (index, frame) in companion.orderedFrames.enumerated() {
            let threshold = game.threshold(at: index)
            if !game.unlocked(frame, character: companion) { return (frame, threshold) }
        }
        return nil
    }

    func chooseCompanion(_ character: CharacterAsset) {
        guard game.owns(character) else { return }
        displayOnDesktop(character, frame: character.idle)
    }

    func chooseStarter(_ character: CharacterAsset) {
        guard update({ try $0.chooseStarter(characterID: character.id, library: library) }) else { return }
        selectedCard = nil
    }

    func startUsageMonitoring() {
        guard usageTask == nil else { return }
        usageTask = Task { [weak self] in
            while !Task.isCancelled {
                guard self != nil else { return }
                await self?.refreshUsage()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    func stopUsageMonitoring() {
        usageTask?.cancel(); usageTask = nil
        toastTask?.cancel(); toastTask = nil
    }

    var usageStatusText: String {
        if usageReading { return "同步中" }
        if usageError != nil { return "同步异常" }
        guard let snapshot = usageSnapshot else { return "未连接" }
        return snapshot.providers.contains { $0.files > 0 } ? "已同步" : "未找到日志"
    }

    func refreshUsage() async {
        guard !usageReading, !developerBusy else { return }
        let generation = usageGeneration
        usageReading = true
        defer { usageReading = false }
        do {
            let snapshot = try await usageScanner.scan(roots: usageRoots)
            guard generation == usageGeneration else { return }
            if developmentTesting {
                usageSnapshot = snapshot
                usageError = snapshot.providers.compactMap(\.error).first
                onUsageChanged?()
                return
            }
            let hatchID = game.hatchCharacterID(library: library)
            var ledger = state.usageLedger ?? UsageLedger()
            let credited = ledger.apply(snapshot.entries)
            let growing = game.readyForGrowth
            let saved = ledger == state.usageLedger || update { next in
                // Finish the first-run draw before usage can unlock anything beyond the idle action.
                if growing, credited > 0 { _ = try next.consume(credited, library: library, hatchCharacterID: hatchID) }
                next.state.usageLedger = ledger
            }
            guard saved else { usageError = "存档未保存，这次用量将稍后重试"; return }
            usageSnapshot = snapshot
            usageError = snapshot.providers.compactMap(\.error).first
            onUsageChanged?()
        } catch { usageError = error.localizedDescription }
    }

    var usageRoots: [UsageProvider: [URL]] {
        var roots = LocalUsageScanner.defaultRoots()
        for (provider, extra) in extraUsageRoots { roots[provider, default: []].append(contentsOf: extra) }
        return roots
    }

    func restoreVisibleState(_ saved: DemoState) {
        let next = DemoGame(state: saved, rules: game.rules)
        UIStrings.language = next.state.language ?? "zh-Hans"
        game = next
    }

    func showUsageSnapshot(_ snapshot: UsageSnapshot) {
        usageSnapshot = snapshot
        usageError = snapshot.providers.compactMap(\.error).first
    }

    func chooseUsageFolder(_ provider: UsageProvider) {
        let chooser = NSOpenPanel()
        chooser.title = L(provider == .codex ? "选择 Codex 用量文件夹" : "选择 Claude Code 用量文件夹")
        chooser.message = L("请选择用量日志文件夹。")
        chooser.canChooseDirectories = true; chooser.canChooseFiles = false
        guard chooser.runModal() == .OK, let folder = chooser.url else { return }
        if !extraUsageRoots[provider, default: []].contains(folder) { extraUsageRoots[provider, default: []].append(folder) }
        if let data = try? JSONEncoder().encode(extraUsageRoots) { UserDefaults.standard.set(data, forKey: "extraUsageRoots") }
        Task { await refreshUsage() }
    }

    func image(_ path: String, thumbnailMaxPixelSize: Int? = nil) -> NSImage? {
        let url = projectRoot.appendingPathComponent(path).standardizedFileURL
        guard url.path.hasPrefix(projectRoot.standardizedFileURL.path + "/") else { return nil }
        let key = (path + (thumbnailMaxPixelSize.map { "#thumb\($0)" } ?? "")) as NSString
        if let image = imageCache.object(forKey: key) { return image }
        let image: NSImage
        if let limit = thumbnailMaxPixelSize {
            let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                           kCGImageSourceCreateThumbnailWithTransform: true,
                           kCGImageSourceThumbnailMaxPixelSize: max(16, min(2048, limit)),
                           kCGImageSourceShouldCacheImmediately: true] as CFDictionary
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
            image = NSImage(cgImage: thumbnail, size: .zero)
        } else {
            guard let loaded = NSImage(contentsOf: url) else { return nil }
            image = loaded
        }
        imageCache.setObject(image, forKey: key, cost: Int(image.size.width * image.size.height * 4))
        return image
    }

    func animation(for file: String) -> AnimationAsset? {
        guard let frame = library.characters.lazy.flatMap({ $0.orderedFrames }).first(where: { $0.file == file }),
              let path = frame.animation else { return nil }
        if let cached = animationCache[path] { return cached }
        guard !unavailableAnimations.contains(path) else { return nil }
        let url = projectRoot.appendingPathComponent(path).standardizedFileURL
        guard url.path.hasPrefix(projectRoot.standardizedFileURL.path + "/"),
              let record = try? AnimationAsset.load(from: url), record.actionId == frame.id else {
            unavailableAnimations.insert(path); return nil
        }
        animationCache[path] = record
        return record
    }

    func changeDifficulty(_ value: Int) {
        guard value != game.difficulty else { return }
        update { try $0.setDifficulty(value, library: library) }
    }

    func buy(_ item: InventoryItem) {
        if update({ try $0.purchase(item) }) { notify(t("已放入仓库")) }
    }

    func use(_ item: InventoryItem) {
        let card = item == .milkTicket ? availableCards.randomElement() : nil
        var success = false
        guard update({ success = try $0.use(item, library: library, roll: Double.random(in: 0..<1), cardID: card?.id) }) else { return }
        if let card { selectedCard = card; notify(t("获得卡片")) }
        else { notify(t(item == .milkCandy ? "孵化进度 +150 Token" : (success ? "升级成功" : "升级未成功"))) }
    }

    // Save one complete transaction before publishing the new visible state.
    @discardableResult
    func update(_ mutation: (inout DemoGame) throws -> Void) -> Bool {
        do {
            var next = game
            try mutation(&next)
            try GameSaveFile.write(next.state, to: saveURL, library: library)
            UIStrings.language = next.state.language ?? "zh-Hans"
            game = next
            onPreferencesChanged?()
            return true
        } catch { notify(error.localizedDescription); return false }
    }

    func preference<T>(_ keyPath: WritableKeyPath<DemoState, T>, _ value: T) {
        update { $0.state[keyPath: keyPath] = value }
    }

    func selectAction(_ frame: FrameAsset) {
        guard game.unlocked(frame, character: companion) else { return }
        update {
            if companion.id == $0.state.activeCharacterId { $0.state.selectedActionId = frame.id }
            $0.state.desktopActionId = frame.id
        }
    }

    func displayOnDesktop(_ character: CharacterAsset, frame: FrameAsset? = nil) {
        guard game.owns(character), game.unlocked(frame ?? character.idle, character: character) else { return }
        guard update({
            $0.state.desktopVisible = true
            $0.state.desktopCharacterId = character.id
            $0.state.desktopActionId = (frame ?? character.idle).id
        }) else { return }
        notify("已切换为\(character.name)")
    }

    func draw(free: Bool) {
        guard let card = availableCards.randomElement() else { return }
        let previousCount = state.collection[card.id, default: 0]
        guard update({ try $0.draw(cardID: card.id, free: free, library: library) }) else { return }
        if state.collection[card.id, default: 0] > previousCount {
            selectedCard = card
            notify(previousCount == 0 ? "获得新卡" : "重复卡 +1")
        }
    }
    func upgrade() {
        var success: Bool?
        guard update({ success = try $0.upgrade(roll: Double.random(in: 0..<1), library: library) }) else { return }
        if let success { notify(success ? "升级成功" : "升级未成功") }
    }
    func startNextEgg() { update { try $0.startWaitingEgg(library: library) } }

    func reloadAssets() {
        let chooser = NSOpenPanel()
        chooser.title = L("选择「奶」项目文件夹")
        chooser.message = L("选择人物与卡片所在的项目文件夹。")
        chooser.canChooseDirectories = true; chooser.canChooseFiles = false
        chooser.allowsMultipleSelection = false; chooser.prompt = L("读取素材")
        guard chooser.runModal() == .OK, let root = chooser.url else { return }
        do {
            let next = try AssetLibrary.load(from: root.appendingPathComponent("05_配置与索引/角色记录.json"))
            guard next.character(state.activeCharacterId) != nil,
                  next.character(state.desktopCharacterId) != nil,
                  ownedCharacters.allSatisfy({ next.character($0.id) != nil }),
                  library.cards.filter({ state.collection[$0.id, default: 0] > 0 }).allSatisfy({ next.card($0.id) != nil }) else { throw GameError.noCharacter }
            try next.validateRuntimeResources(at: root)
            projectRoot = root; library = next; imageCache.removeAllObjects(); animationCache.removeAll(); unavailableAnimations.removeAll(); onPreferencesChanged?()
            notify("素材已更新")
        } catch { notify(error.localizedDescription) }
    }

    func openHelp() {
        let name = state.language == "en" ? "Usage and Privacy.md" : "使用与隐私说明.md"
        let bundled = Bundle.main.resourceURL?.appendingPathComponent(name)
        let source = projectRoot.appendingPathComponent("07_软件开发/" + name)
        if let url = [bundled, source].compactMap({ $0 }).first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            NSWorkspace.shared.open(url)
        }
    }

    func notify(_ text: String) {
        toastTask?.cancel(); toast = t(text)
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}

func compact(_ value: Int) -> String {
    if value >= 1_000_000 {
        var amount = String(format: "%.2f", Double(value) / 1_000_000)
        while amount.last == "0" { amount.removeLast() }
        if amount.last == "." { amount.removeLast() }
        return amount + "M"
    }
    if value >= 1_000 { return String(format: "%.0fK", Double(value) / 1_000) }
    return String(value)
}

func rarityColor(_ rarity: String) -> Color {
    switch rarity {
    case "稀有": Color(red: 0.44, green: 0.76, blue: 0.98)
    case "史诗": Color(red: 0.76, green: 0.58, blue: 0.99)
    case "传说": Color(red: 1, green: 0.73, blue: 0.28)
    default: Color.secondary
    }
}

import SwiftUI
