import AppKit
import SwiftUI
import NaijiaCore

@main
struct NaijiaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: AppStore?
    private var panel: SidebarPanel?
    private var pet: NSPanel?
    private var petView: PetCanvas?
    private var status: NSStatusItem?
    private var clickMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var accessibilityObserver: NSObjectProtocol?
    private let sidebarPresentation = SidebarPresentation()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil); return
        }
        NSApp.setActivationPolicy(.regular)
        do {
            let root = resolveRoot()
            let store = try loadStore(root: root)
            self.store = store
            store.onPreferencesChanged = { [weak self] in self?.syncPreferences() }
            store.onUsageChanged = { [weak self] in self?.updateStatusItem() }
            store.onResetDesktopPosition = { [weak self] in self?.resetDesktopPosition() }
            makeSidebar(store)
            makePet(store)
            makeMenuBar()
            syncPreferences()
            showSidebar()
            store.startUsageMonitoring()
            screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    if let pet = self?.pet { self?.clampPet(pet) }
                    if let panel = self?.panel { self?.clamp(panel) }
                }
            }
            accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.syncPreferences() }
            }
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.store?.state.pinned == false else { return }
                    self.hideSidebar()
                }
            }
        } catch StartupRecovery.cancelled {
            NSApp.terminate(nil)
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = L("\(ApplicationIdentity.displayName)暂时无法启动")
            alert.informativeText = L(error.localizedDescription) + "\n\n" + L("请检查应用资源或存档文件，已有存档不会被覆盖。")
            alert.addButton(withTitle: L("退出")); alert.addButton(withTitle: L("打开存档文件夹"))
            if alert.runModal() == .alertSecondButtonReturn { openSaveFolder() }
            NSApp.terminate(nil)
        }
    }

    private enum StartupRecovery: Error { case cancelled }

    private func loadStore(root: URL) throws -> AppStore {
        do { return try AppStore(projectRoot: root) }
        catch SaveFileError.unreadable {
            let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent(ApplicationIdentity.dataDirectory, isDirectory: true)
            let save = folder.appendingPathComponent("正式存档.json")
            let library = try AssetLibrary.load(from: root.appendingPathComponent("05_配置与索引/角色记录.json"))
            guard (try? GameSaveFile.read(from: GameSaveFile.backupURL(for: save), library: library)) != nil else { throw SaveFileError.unreadable }
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = L("存档无法读取")
            alert.informativeText = L("可以恢复上次有效存档。损坏的原文件会另外保留，恢复可能回退最近一次操作。")
            alert.addButton(withTitle: L("恢复上次存档")); alert.addButton(withTitle: L("退出")); alert.addButton(withTitle: L("打开存档文件夹"))
            let response = alert.runModal()
            guard response == .alertFirstButtonReturn else {
                if response == .alertThirdButtonReturn { NSWorkspace.shared.open(folder) }
                throw StartupRecovery.cancelled
            }
            try GameSaveFile.restoreBackup(for: save, library: library)
            return try AppStore(projectRoot: root)
        }
    }

    private func openSaveFolder() {
        guard let folder = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(ApplicationIdentity.dataDirectory, isDirectory: true) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    private func resolveRoot() -> URL {
        if let path = ProcessInfo.processInfo.environment["NAIJIA_PROJECT_ROOT"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        if let resources = Bundle.main.resourceURL {
            let bundled = resources.appendingPathComponent("项目素材")
            if FileManager.default.fileExists(atPath: bundled.appendingPathComponent("05_配置与索引/角色记录.json").path) { return bundled }
        }
        // A relocated complete project works without rebuilding absolute paths.
        var candidate = Bundle.main.bundleURL
        for _ in 0..<8 {
            candidate.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("05_配置与索引/角色记录.json").path) { return candidate }
        }
        let path = Bundle.main.object(forInfoDictionaryKey: "NaijiaProjectRoot") as? String ?? FileManager.default.currentDirectoryPath
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func makeSidebar(_ store: AppStore) {
        let panel = SidebarPanel(contentRect: NSRect(x: 0, y: 0, width: PanelMetrics.width, height: PanelMetrics.height), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "\(ApplicationIdentity.displayName) · 侧边浮窗"
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: PanelRoot(store: store,
            onClose: { [weak self] in self?.hideSidebar() },
            onHeightChanged: { [weak self, weak panel] height in
                guard let panel else { return }
                let top = panel.frame.maxY
                let frame = NSRect(x: panel.frame.minX, y: top - height, width: PanelMetrics.width, height: height)
                self?.sidebarPresentation.resize(panel, to: self?.clampedFrame(frame) ?? frame)
            }))
        panel.setFrameAutosaveName("NaijiaSidebar")
        if !panel.setFrameUsingName("NaijiaSidebar"), let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: visible.maxX - 382, y: visible.maxY - 666))
        }
        panel.setContentSize(NSSize(width: PanelMetrics.width, height: PanelMetrics.height))
        self.panel = panel
        clamp(panel)
    }

    private func makePet(_ store: AppStore) {
        let panel = PassivePetPanel(contentRect: NSRect(x: 0, y: 0, width: store.state.petSize, height: store.state.petSize), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "\(ApplicationIdentity.displayName) · 桌面伙伴"
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = false; panel.hidesOnDeactivate = false
        panel.level = .floating; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = PetCanvas()
        view.onClick = { [weak self] in self?.toggleSidebar() }
        view.onRightClick = { [weak self] event in self?.showPetMenu(event) }
        view.onDragFinished = { [weak self] in
            guard let self, let pet = self.pet else { return }
            self.clampPet(pet)
            UserDefaults.standard.set(NSStringFromPoint(pet.frame.origin), forKey: "petOrigin")
        }
        panel.contentView = view
        if let position = UserDefaults.standard.string(forKey: "petOrigin") {
            panel.setFrameOrigin(NSPointFromString(position))
        } else if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 145, y: screen.visibleFrame.minY + 35))
        }
        pet = panel; petView = view
        clampPet(panel)
    }

    private func makeMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = Bundle.main.bundleIdentifier ?? "NaijiaMenuBar"
        item.isVisible = true
        item.button?.target = self; item.button?.action = #selector(statusClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.imagePosition = .imageLeading
        item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        status = item
    }

    private func syncPreferences() {
        guard let store else { return }
        panel?.title = L("\(ApplicationIdentity.displayName) · 侧边浮窗")
        pet?.title = L("\(ApplicationIdentity.displayName) · 桌面伙伴")
        panel?.level = store.state.pinned ? .floating : .normal
        let appearance: NSAppearance?
        switch store.state.appearance {
        case "light": appearance = NSAppearance(named: .aqua)
        case "dark": appearance = NSAppearance(named: .darkAqua)
        default: appearance = nil
        }
        panel?.appearance = appearance
        if let animation = store.animation(for: store.desktopFrame.file) {
            petView?.configureAnimation(key: store.projectRoot.path + animation.actionId,
                images: animation.frames.compactMap { store.image($0.file) },
                durations: animation.frameDurationsMs, loop: animation.loop,
                playing: store.state.desktopVisible && store.game.owns(store.desktopCharacter))
        } else {
            petView?.configureAnimation(key: store.desktopFrame.id, images: [store.image(store.desktopFrame.file)].compactMap { $0 },
                durations: [180], playing: store.state.desktopVisible && store.game.owns(store.desktopCharacter))
        }
        petView?.setAccessibilityLabel(L("\(store.desktopCharacter.name)，\(store.desktopFrame.name)。点击打开\(ApplicationIdentity.displayName)"))
        petView?.toolTip = L("\(store.desktopCharacter.name) · \(store.desktopFrame.name)\n点击打开\(ApplicationIdentity.displayName)，拖动移动，右键切换动作")
        if let pet {
            pet.setContentSize(NSSize(width: store.state.petSize, height: store.state.petSize))
            clampPet(pet)
            if store.state.desktopVisible && store.game.owns(store.desktopCharacter) { pet.orderFrontRegardless() } else { pet.orderOut(nil) }
        }
        if sidebarPresentation.isPresented { panel?.orderFrontRegardless() }
        updateStatusItem()
    }

    private func updateStatusItem() {
        guard let store else { return }
        if let button = status?.button {
            if store.game.owns(store.desktopCharacter), let source = store.image(store.desktopFrame.file) {
                let icon = NSImage(size: NSSize(width: 22, height: 22))
                icon.lockFocus(); NSGraphicsContext.current?.imageInterpolation = .none
                source.draw(in: NSRect(x: 0, y: 0, width: 22, height: 22))
                icon.unlockFocus(); icon.isTemplate = false
                button.image = icon
            } else {
                button.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "选择\(ApplicationIdentity.displayName)伙伴")
            }
            let tokens = store.developmentTesting ? store.state.totalTokens : (store.usageSnapshot?.today ?? 0)
            button.title = " \(compact(tokens))"
            button.toolTip = L("\(ApplicationIdentity.displayName) · \(store.developmentTesting ? "开发测试状态" : "今日 Codex + Claude Code 用量") · 点击展开")
        }
    }

    private func clampPet(_ window: NSWindow) {
        window.setFrameOrigin(DesktopPetPlacement.constrain(window.frame, to: NSScreen.screens.map(\.frame)).origin)
    }

    private func resetDesktopPosition() {
        guard let pet, let screen = NSScreen.main else { return }
        pet.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - pet.frame.width - 24, y: screen.visibleFrame.minY + 24))
        clampPet(pet)
        UserDefaults.standard.set(NSStringFromPoint(pet.frame.origin), forKey: "petOrigin")
        if let store { store.preference(\.desktopVisible, true) }
    }

    private func clamp(_ window: NSWindow) {
        window.setFrameOrigin(clampedFrame(window.frame).origin)
    }

    private func clampedFrame(_ frame: NSRect) -> NSRect {
        let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(frame) }) ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return frame }
        let x = min(max(frame.minX, visible.minX + 8), max(visible.minX + 8, visible.maxX - frame.width - 8))
        let y = min(max(frame.minY, visible.minY + 8), max(visible.minY + 8, visible.maxY - frame.height - 8))
        return NSRect(origin: NSPoint(x: x, y: y), size: frame.size)
    }

    private func showSidebar() {
        guard let panel else { return }
        store?.panelVisible = true; clamp(panel)
        NSApp.activate(ignoringOtherApps: true)
        sidebarPresentation.show(panel)
    }
    private func hideSidebar() {
        store?.panelVisible = false
        if let panel { sidebarPresentation.hide(panel) }
    }
    private func toggleSidebar() { sidebarPresentation.isPresented ? hideSidebar() : showSidebar() }
    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { showStatusMenu() } else { toggleSidebar() }
    }

    private func menuItem(_ title: String, selector: Selector, represented: Any? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: L(title), action: selector, keyEquivalent: "")
        item.target = self; item.representedObject = represented; return item
    }
    private func showStatusMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(menuItem("打开\(ApplicationIdentity.displayName)", selector: #selector(openSidebar)))
        menu.addItem(menuItem(store?.state.desktopVisible == true ? "隐藏桌面伙伴" : "显示桌面伙伴", selector: #selector(togglePet)))
        menu.addItem(menuItem("将伙伴移回屏幕", selector: #selector(recoverPet)))
        menu.addItem(.separator())
        menu.addItem(menuItem("退出\(ApplicationIdentity.displayName)", selector: #selector(quit)))
        status?.menu = menu; status?.button?.performClick(nil); status?.menu = nil
    }
    private func showPetMenu(_ event: NSEvent) {
        guard let store, let petView else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(menuItem("打开\(ApplicationIdentity.displayName)", selector: #selector(openSidebar)))
        menu.addItem(.separator())
        for frame in store.desktopCharacter.orderedFrames {
            let item = menuItem(frame.name, selector: #selector(petPose(_:)), represented: frame.id)
            item.state = frame.id == store.state.desktopActionId ? .on : .off
            item.isEnabled = store.game.unlocked(frame, character: store.desktopCharacter)
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(menuItem("隐藏桌面伙伴", selector: #selector(togglePet)))
        NSMenu.popUpContextMenu(menu, with: event, for: petView)
    }
    @objc private func petPose(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String, let store,
              let frame = store.desktopCharacter.orderedFrames.first(where: { $0.id == id }) else { return }
        store.displayOnDesktop(store.desktopCharacter, frame: frame)
    }
    @objc private func openSidebar() { showSidebar() }
    @objc private func togglePet() { if let store { store.preference(\.desktopVisible, !store.state.desktopVisible) } }
    @objc private func recoverPet() { resetDesktopPosition() }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSidebar(); return true }
    func applicationWillTerminate(_ notification: Notification) {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
        store?.stopUsageMonitoring()
        petView?.stopAnimation()
        panel?.saveFrame(usingName: "NaijiaSidebar")
    }
}

final class SidebarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class PassivePetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor
final class PetCanvas: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    private var animationTask: Task<Void, Never>?
    private var animationKey = ""
    private var animationImages: [NSImage] = []
    private var animationDurations: [Int] = []
    private var animationPlaying = false
    private var animationLoops = true
    private var reducedMotion = false

    func stopAnimation() { animationTask?.cancel(); animationTask = nil }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { stopAnimation() }
        super.viewWillMove(toWindow: newWindow)
    }

    func configureAnimation(key: String, images: [NSImage], durations: [Int], loop: Bool = true, playing: Bool) {
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let changed = key != animationKey || playing != animationPlaying || loop != animationLoops || reduced != reducedMotion
        animationImages = images; animationDurations = durations
        guard changed || animationTask == nil else { return }
        animationTask?.cancel(); animationTask = nil
        animationKey = key; animationPlaying = playing; animationLoops = loop; reducedMotion = reduced
        image = images.first
        guard playing, !reduced, images.count > 1, images.count == durations.count else { return }
        animationTask = Task { @MainActor [weak self] in
            var index = 0
            while !Task.isCancelled {
                guard let delay = self?.displayAnimationFrame(index) else { return }
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled, let count = self?.animationImages.count, count > 0 else { return }
                if self?.animationLoops == false && index == count - 1 { return }
                index = (index + 1) % count
            }
        }
    }

    private func displayAnimationFrame(_ index: Int) -> Int? {
        guard animationPlaying, animationImages.indices.contains(index), animationDurations.indices.contains(index) else { return nil }
        image = animationImages[index]
        return animationDurations[index]
    }
    var onClick: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?
    var onDragFinished: (() -> Void)?
    private var startMouse = NSPoint.zero
    private var startWindow = NSPoint.zero
    override var isOpaque: Bool { false }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityPerformPress() -> Bool { onClick?(); return true }
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.cgContext.clear(bounds)
        NSGraphicsContext.current?.imageInterpolation = .none
        image?.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
    }
    override func mouseDown(with event: NSEvent) { startMouse = NSEvent.mouseLocation; startWindow = window?.frame.origin ?? .zero }
    override func mouseDragged(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        window?.setFrameOrigin(NSPoint(x: startWindow.x + point.x - startMouse.x, y: startWindow.y + point.y - startMouse.y))
    }
    override func mouseUp(with event: NSEvent) {
        let end = NSEvent.mouseLocation
        if hypot(end.x - startMouse.x, end.y - startMouse.y) < 4 { onClick?() } else { onDragFinished?() }
    }
    override func rightMouseDown(with event: NSEvent) { onRightClick?(event) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
}
